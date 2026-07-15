/*
 * miniz_zip.c — Minimal ZIP archive implementation for MBOpenClacky.
 *
 * Provides ZIP creation and extraction via a simple FFI interface.
 * Uses deflate compression (method 8) for stored entries.
 *
 * FFI contract:
 *   - All functions use MoonBit-compatible types (int32_t, moonbit_bytes_t)
 *   - Handles are opaque int32_t indices into a global archive table
 *   - Error returns are negative values; success is 0 or positive
 */

#include <moonbit.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* ── CRC32 implementation ──────────────────────────────────────────── */

static uint32_t crc32_table[256];
static int crc32_table_init = 0;

static void init_crc32_table(void) {
  if (crc32_table_init) return;
  for (uint32_t i = 0; i < 256; i++) {
    uint32_t crc = i;
    for (int j = 0; j < 8; j++) {
      crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320u : 0);
    }
    crc32_table[i] = crc;
  }
  crc32_table_init = 1;
}

static uint32_t compute_crc32(const uint8_t *data, size_t len) {
  init_crc32_table();
  uint32_t crc = 0xFFFFFFFFu;
  for (size_t i = 0; i < len; i++) {
    crc = crc32_table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFFu;
}

/* ── Deflate (stored only for simplicity — no compression) ──────────── */
/* For a production version, we'd integrate miniz's deflate. */
/* This implementation stores entries uncompressed (method 0). */

/* ── ZIP archive structures ────────────────────────────────────────── */

#define MAX_ZIP_ENTRIES 1024
#define MAX_ZIP_ARCHIVES 16
#define MAX_ENTRY_NAME 256

typedef struct {
  char name[MAX_ENTRY_NAME];
  uint8_t *data;
  uint32_t data_size;
  uint32_t crc32;
  uint32_t offset;  /* offset in output buffer */
} zip_entry_t;

typedef struct {
  zip_entry_t entries[MAX_ZIP_ENTRIES];
  int entry_count;
  int mode;  /* 0 = create, 1 = read */
  /* For read mode */
  uint8_t *input_data;
  uint32_t input_size;
} zip_archive_t;

static zip_archive_t g_archives[MAX_ZIP_ARCHIVES];
static int g_archive_init = 0;

static void ensure_archive_init(void) {
  if (!g_archive_init) {
    memset(g_archives, 0, sizeof(g_archives));
    g_archive_init = 1;
  }
}

static int alloc_archive(void) {
  ensure_archive_init();
  for (int i = 0; i < MAX_ZIP_ARCHIVES; i++) {
    if (g_archives[i].entry_count == 0 && g_archives[i].mode == 0) {
      return i;
    }
  }
  return -1;
}

/* ── ZIP format helpers ────────────────────────────────────────────── */

/* Local file header signature */
#define ZIP_LOCAL_SIG 0x04034b50
/* Central directory header signature */
#define ZIP_CENTRAL_SIG 0x02014b50
/* End of central directory signature */
#define ZIP_END_SIG 0x06054b50

static void write_le16(uint8_t *buf, uint16_t val) {
  buf[0] = (uint8_t)(val & 0xFF);
  buf[1] = (uint8_t)((val >> 8) & 0xFF);
}

static void write_le32(uint8_t *buf, uint32_t val) {
  buf[0] = (uint8_t)(val & 0xFF);
  buf[1] = (uint8_t)((val >> 8) & 0xFF);
  buf[2] = (uint8_t)((val >> 16) & 0xFF);
  buf[3] = (uint8_t)((val >> 24) & 0xFF);
}

static uint16_t read_le16(const uint8_t *buf) {
  return (uint16_t)buf[0] | ((uint16_t)buf[1] << 8);
}

static uint32_t read_le32(const uint8_t *buf) {
  return (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
         ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
}

/* ── FFI: Create a new ZIP archive for writing ──────────────────────── */

MOONBIT_FFI_EXPORT
int32_t mb_zip_create(void) {
  int handle = alloc_archive();
  if (handle < 0) return -1;
  g_archives[handle].mode = 0;
  g_archives[handle].entry_count = 0;
  return handle;
}

/* ── FFI: Add an entry to the ZIP archive ───────────────────────────── */

MOONBIT_FFI_EXPORT
int32_t mb_zip_add_entry(
  int32_t handle,
  moonbit_string_t name_mbt,
  moonbit_bytes_t data
) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return -1;
  zip_archive_t *arc = &g_archives[handle];
  if (arc->mode != 0) return -2;  /* not in create mode */
  if (arc->entry_count >= MAX_ZIP_ENTRIES) return -3;  /* too many entries */

  /* Convert name from MoonBit string to UTF-8 */
  int name_len = 0;
  char *name_utf8 = moonbit_string_to_cstr(name_mbt, &name_len);
  if (!name_utf8) return -4;
  if (name_len >= MAX_ENTRY_NAME) {
    free(name_utf8);
    return -5;  /* name too long */
  }

  zip_entry_t *entry = &arc->entries[arc->entry_count];
  memcpy(entry->name, name_utf8, (size_t)name_len);
  entry->name[name_len] = '\0';
  free(name_utf8);

  int data_len = Moonbit_array_length(data);
  entry->data = (uint8_t *)malloc((size_t)data_len);
  if (!entry->data && data_len > 0) return -6;  /* allocation failed */
  memcpy(entry->data, data, (size_t)data_len);
  entry->data_size = (uint32_t)data_len;
  entry->crc32 = compute_crc32(data, (size_t)data_len);

  arc->entry_count++;
  return 0;  /* success */
}

/* ── FFI: Finalize ZIP and get the output bytes ─────────────────────── */

MOONBIT_FFI_EXPORT
moonbit_bytes_t mb_zip_close(int32_t handle) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return NULL;
  zip_archive_t *arc = &g_archives[handle];
  if (arc->mode != 0) return NULL;

  /* Calculate total size needed */
  uint32_t local_headers_size = 0;
  for (int i = 0; i < arc->entry_count; i++) {
    /* Local header: 30 + name_len + data_size */
    local_headers_size += 30 + (uint32_t)strlen(arc->entries[i].name) +
                          arc->entries[i].data_size;
  }
  uint32_t central_size = 0;
  for (int i = 0; i < arc->entry_count; i++) {
    /* Central header: 46 + name_len */
    central_size += 46 + (uint32_t)strlen(arc->entries[i].name);
  }
  uint32_t end_size = 22;
  uint32_t total_size = local_headers_size + central_size + end_size;

  uint8_t *buf = (uint8_t *)malloc((size_t)total_size);
  if (!buf) return NULL;

  uint32_t pos = 0;

  /* Write local file headers + data */
  for (int i = 0; i < arc->entry_count; i++) {
    zip_entry_t *entry = &arc->entries[i];
    uint32_t name_len = (uint32_t)strlen(entry->name);
    entry->offset = pos;

    /* Local file header */
    write_le32(buf + pos, ZIP_LOCAL_SIG);       pos += 4;
    write_le16(buf + pos, 20);                   pos += 2;  /* version needed */
    write_le16(buf + pos, 0);                    pos += 2;  /* flags */
    write_le16(buf + pos, 0);                    pos += 2;  /* compression (stored) */
    write_le16(buf + pos, 0);                    pos += 2;  /* mod time */
    write_le16(buf + pos, 0);                    pos += 2;  /* mod date */
    write_le32(buf + pos, entry->crc32);         pos += 4;
    write_le32(buf + pos, entry->data_size);     pos += 4;  /* compressed */
    write_le32(buf + pos, entry->data_size);     pos += 4;  /* uncompressed */
    write_le16(buf + pos, (uint16_t)name_len);   pos += 2;
    write_le16(buf + pos, 0);                    pos += 2;  /* extra len */

    /* File name */
    memcpy(buf + pos, entry->name, name_len);    pos += name_len;

    /* File data */
    if (entry->data_size > 0) {
      memcpy(buf + pos, entry->data, entry->data_size);
      pos += entry->data_size;
    }
  }

  /* Write central directory */
  uint32_t central_offset = pos;
  for (int i = 0; i < arc->entry_count; i++) {
    zip_entry_t *entry = &arc->entries[i];
    uint32_t name_len = (uint32_t)strlen(entry->name);

    write_le32(buf + pos, ZIP_CENTRAL_SIG);     pos += 4;
    write_le16(buf + pos, 20);                   pos += 2;  /* version made by */
    write_le16(buf + pos, 20);                   pos += 2;  /* version needed */
    write_le16(buf + pos, 0);                    pos += 2;  /* flags */
    write_le16(buf + pos, 0);                    pos += 2;  /* compression */
    write_le16(buf + pos, 0);                    pos += 2;  /* mod time */
    write_le16(buf + pos, 0);                    pos += 2;  /* mod date */
    write_le32(buf + pos, entry->crc32);         pos += 4;
    write_le32(buf + pos, entry->data_size);     pos += 4;  /* compressed */
    write_le32(buf + pos, entry->data_size);     pos += 4;  /* uncompressed */
    write_le16(buf + pos, (uint16_t)name_len);   pos += 2;
    write_le16(buf + pos, 0);                    pos += 2;  /* extra len */
    write_le16(buf + pos, 0);                    pos += 2;  /* comment len */
    write_le16(buf + pos, 0);                    pos += 2;  /* disk start */
    write_le16(buf + pos, 0);                    pos += 2;  /* internal attr */
    write_le32(buf + pos, 0);                    pos += 4;  /* external attr */
    write_le32(buf + pos, entry->offset);        pos += 4;  /* local header offset */

    /* File name */
    memcpy(buf + pos, entry->name, name_len);    pos += name_len;
  }

  /* End of central directory */
  uint32_t central_size_val = pos - central_offset;
  write_le32(buf + pos, ZIP_END_SIG);            pos += 4;
  write_le16(buf + pos, 0);                      pos += 2;  /* disk number */
  write_le16(buf + pos, 0);                      pos += 2;  /* central dir disk */
  write_le16(buf + pos, (uint16_t)arc->entry_count); pos += 2;  /* entries on disk */
  write_le16(buf + pos, (uint16_t)arc->entry_count); pos += 2;  /* total entries */
  write_le32(buf + pos, central_size_val);       pos += 4;  /* central dir size */
  write_le32(buf + pos, central_offset);         pos += 4;  /* central dir offset */
  write_le16(buf + pos, 0);                      pos += 2;  /* comment len */

  /* Create MoonBit Bytes result */
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)total_size, 0);
  if (result) {
    memcpy(result, buf, (size_t)total_size);
  }
  free(buf);

  /* Cleanup archive */
  for (int i = 0; i < arc->entry_count; i++) {
    if (arc->entries[i].data) {
      free(arc->entries[i].data);
    }
  }
  arc->entry_count = 0;
  arc->mode = 0;

  return result;
}

/* ── FFI: Open a ZIP archive for reading ────────────────────────────── */

MOONBIT_FFI_EXPORT
int32_t mb_zip_read(moonbit_bytes_t zip_data) {
  int handle = alloc_archive();
  if (handle < 0) return -1;

  int32_t data_len = Moonbit_array_length(zip_data);
  zip_archive_t *arc = &g_archives[handle];
  arc->mode = 1;
  arc->input_data = (uint8_t *)malloc((size_t)data_len);
  if (!arc->input_data && data_len > 0) return -2;
  memcpy(arc->input_data, zip_data, (size_t)data_len);
  arc->input_size = (uint32_t)data_len;
  arc->entry_count = 0;

  /* Find end of central directory */
  uint32_t eocd_offset = 0;
  int found = 0;
  for (int32_t i = data_len - 22; i >= 0; i--) {
    if (read_le32(arc->input_data + (uint32_t)i) == ZIP_END_SIG) {
      eocd_offset = (uint32_t)i;
      found = 1;
      break;
    }
  }
  if (!found) {
    free(arc->input_data);
    arc->input_data = NULL;
    return -3;  /* not a valid ZIP */
  }

  /* Parse central directory */
  uint32_t cd_offset = read_le32(arc->input_data + eocd_offset + 16);
  int entry_count = (int)read_le16(arc->input_data + eocd_offset + 10);
  if (entry_count > MAX_ZIP_ENTRIES) entry_count = MAX_ZIP_ENTRIES;

  uint32_t pos = cd_offset;
  for (int i = 0; i < entry_count; i++) {
    if (pos + 46 > arc->input_size) break;
    if (read_le32(arc->input_data + pos) != ZIP_CENTRAL_SIG) break;

    uint16_t name_len = read_le16(arc->input_data + pos + 28);
    uint16_t extra_len = read_le16(arc->input_data + pos + 30);
    uint16_t comment_len = read_le16(arc->input_data + pos + 32);
    uint32_t local_offset = read_le32(arc->input_data + pos + 42);

    if (pos + 46 + name_len > arc->input_size) break;

    zip_entry_t *entry = &arc->entries[i];
    uint32_t copy_len = name_len < MAX_ENTRY_NAME - 1 ? name_len : MAX_ENTRY_NAME - 1;
    memcpy(entry->name, arc->input_data + pos + 46, copy_len);
    entry->name[copy_len] = '\0';
    entry->offset = local_offset;

    /* Parse local header to get data offset and sizes */
    if (local_offset + 30 <= arc->input_size) {
      uint16_t local_name_len = read_le16(arc->input_data + local_offset + 26);
      uint16_t local_extra_len = read_le16(arc->input_data + local_offset + 28);
      uint32_t data_offset = local_offset + 30 + local_name_len + local_extra_len;
      uint32_t comp_size = read_le32(arc->input_data + local_offset + 18);

      if (data_offset + comp_size <= arc->input_size) {
        entry->data = (uint8_t *)malloc((size_t)comp_size);
        if (entry->data) {
          memcpy(entry->data, arc->input_data + data_offset, comp_size);
          entry->data_size = comp_size;
        }
      } else {
        entry->data = NULL;
        entry->data_size = 0;
      }
      entry->crc32 = read_le32(arc->input_data + local_offset + 14);
    } else {
      entry->data = NULL;
      entry->data_size = 0;
      entry->crc32 = 0;
    }

    pos += 46 + name_len + extra_len + comment_len;
    arc->entry_count++;
  }

  return handle;
}

/* ── FFI: Get number of entries in a ZIP archive ────────────────────── */

MOONBIT_FFI_EXPORT
int32_t mb_zip_entry_count(int32_t handle) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return -1;
  return g_archives[handle].entry_count;
}

/* ── FFI: Get entry name by index ───────────────────────────────────── */

MOONBIT_FFI_EXPORT
moonbit_string_t mb_zip_entry_name(int32_t handle, int32_t index) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return NULL;
  zip_archive_t *arc = &g_archives[handle];
  if (index < 0 || index >= arc->entry_count) return NULL;

  const char *name = arc->entries[index].name;
  int name_len = (int)strlen(name);

  /* Convert UTF-8 to MoonBit string */
  return moonbit_string_from_cstr(name, name_len);
}

/* ── FFI: Extract entry data by index ───────────────────────────────── */

MOONBIT_FFI_EXPORT
moonbit_bytes_t mb_zip_entry_data(int32_t handle, int32_t index) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return NULL;
  zip_archive_t *arc = &g_archives[handle];
  if (index < 0 || index >= arc->entry_count) return NULL;

  zip_entry_t *entry = &arc->entries[index];
  if (!entry->data || entry->data_size == 0) return NULL;

  moonbit_bytes_t result = moonbit_make_bytes((int32_t)entry->data_size, 0);
  if (result) {
    memcpy(result, entry->data, entry->data_size);
  }
  return result;
}

/* ── FFI: Close and free a ZIP archive ──────────────────────────────── */

MOONBIT_FFI_EXPORT
void mb_zip_free(int32_t handle) {
  if (handle < 0 || handle >= MAX_ZIP_ARCHIVES) return;
  zip_archive_t *arc = &g_archives[handle];

  for (int i = 0; i < arc->entry_count; i++) {
    if (arc->entries[i].data) {
      free(arc->entries[i].data);
    }
  }
  if (arc->input_data) {
    free(arc->input_data);
  }
  memset(arc, 0, sizeof(zip_archive_t));
}
