# i18n 翻译工具脚本说明

本目录包含用于维护 MBOpenClacky 项目国际化翻译的工具脚本。

## 工具列表

### 1. `extract_i18n_keys.ps1`
**功能**：从代码和字典中提取翻译key，进行差异分析

**用途**：
- 扫描 `web/mb/main/` 目录下所有 `.mbt` 文件
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

### 2. `verify_translation_coverage.py`
**功能**：验证翻译覆盖率，检查代码中使用的key是否都有翻译

**用途**：
- 扫描所有 `.mbt` 文件中的翻译调用
- 检查这些key是否在英文和中文字典中存在
- 计算翻译覆盖率百分比

**使用方法**：
```bash
python scripts/verify_translation_coverage.py
```

**输出示例**：
```
English dictionary keys: 692
Chinese dictionary keys: 692
Code keys found: 519
Translation coverage:
  English: 99.4%
  Chinese: 99.4%
```

### 3. `dedup_zh_dict.py`
**功能**：去重中文翻译字典，移除重复的key

**用途**：
- 检测并移除 `i18n_dict_zh.mbt` 中的重复key
- 保留第一个出现的key，删除后续重复项

**使用方法**：
```bash
python scripts/dedup_zh_dict.py
```

**输出示例**：
```
Removed 456 duplicate keys
New dictionary has 704 lines
Unique keys: 692
```

### 4. `check_zh_keys.py`
**功能**：检查中英文词典的key对称性

**用途**：
- 对比英文和中文字典的key集合
- 识别缺失和多余的key
- 确保两个字典完全对称

**使用方法**：
```bash
python scripts/check_zh_keys.py
```

**输出示例**：
```
English dictionary keys: 692
Chinese dictionary keys: 692
Missing from Chinese: 0
Missing from English: 0
Common keys: 692
```

## 使用场景

### 添加新功能后
1. 运行 `extract_i18n_keys.ps1` 检查新key是否已添加到字典
2. 运行 `verify_translation_coverage.py` 确认翻译覆盖率

### 定期维护
1. 运行 `check_zh_keys.py` 检查中英文词典一致性
2. 运行 `dedup_zh_dict.py` 清理重复key

### 代码审查
1. 运行 `verify_translation_coverage.py` 确保翻译完整性
2. 检查输出文件中的缺失key列表

## 注意事项

1. 这些脚本假设翻译key使用点分隔格式（如 `"sessions.title"`）
2. 脚本会过滤掉API路径等非翻译字符串
3. 建议在修改字典文件前先运行检查脚本
4. 所有脚本都应在项目根目录下运行