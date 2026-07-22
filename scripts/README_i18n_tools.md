# i18n 翻译工具脚本说明

本目录包含用于维护 MBOpenClacky 项目国际化翻译的工具脚本。

## 工具列表

### `extract_i18n_keys.ps1`
**功能**：从代码和字典中提取翻译key，进行差异分析

**用途**：
- 扫描指定目录下所有 `.mbt` 文件
- 提取 `t("key")` 和 `t1("key", ...)` 调用中的翻译key
- 对比英文和中文字典，识别缺失、多余、不对称的key
- 按前缀分组统计缺失key

**使用方法**：
```powershell
powershell -ExecutionPolicy Bypass -File scripts/extract_i18n_keys.ps1
```

**输出文件**：
- `missing_keys_clean.txt` - 缺失的翻译key
- `extra_keys_en.txt` / `extra_keys_zh.txt` - 字典中多余的key
- `en_only_keys.txt` / `zh_only_keys.txt` - 不对称的key

> **注意**：该脚本当前的默认路径（`web/mb/main/i18n_dict_*.mbt`）指向已退役的
> MoonBit SPA 前端，直接使用会报错；如需复用，请先把脚本内的路径改为当前
> 实际的 i18n 字典位置。

## 注意事项

1. 脚本假设翻译key使用点分隔格式（如 `"sessions.title"`）
2. 脚本会过滤掉API路径等非翻译字符串
3. 所有脚本都应在项目根目录下运行
