# Benchmark Infrastructure

This directory contains the benchmark infrastructure for MBOpenClacky.

## Structure

```
benchmark/
├── scenarios/          # Benchmark scenario definitions
│   ├── llm_latency.json    # LLM response latency benchmark
│   └── tool_exec.json      # Tool execution time benchmark
├── results/            # Benchmark results (auto-generated)
└── README.md          # This file
```

## Usage

### Running Benchmarks

Run all scenarios in the default directory:

```bash
moon run cmd -- benchmark benchmark/scenarios
```

Run with custom parameters:

```bash
moon run cmd -- benchmark benchmark/scenarios \
  --iterations 20 \
  --warmup 5 \
  --threshold 15.0 \
  --output benchmark/results
```

### Command Options

- `scenario_dir`: Directory containing benchmark scenario JSON files
- `--iterations N`: Number of iterations per scenario (default: 10)
- `--warmup N`: Number of warmup iterations (default: 3)
- `--threshold PCT`: Regression threshold percentage (default: 10.0)
- `--output DIR`: Output directory for results (default: benchmark/results)

### Scenario File Format

Scenario files are JSON documents with the following structure:

```json
{
  "name": "scenario_name",
  "description": "Description of what this benchmark measures",
  "tool": "tool_name",
  "parameters": {
    "param1": "value1",
    "param2": "value2"
  },
  "iterations": 10,
  "warmup": 3
}
```

### Results

Results are saved in `benchmark/results/<scenario_name>/` with timestamps:

```
benchmark/results/
├── llm_latency/
│   ├── 2026-08-11T21-30-00.json
│   └── 2026-08-11T22-00-00.json
└── tool_exec/
    └── 2026-08-11T21-35-00.json
```

Each result file contains:

```json
{
  "scenario_name": "llm_latency",
  "timestamp": 1691788200000,
  "stats": {
    "min_ms": 100,
    "max_ms": 200,
    "avg_ms": 150.0,
    "p50_ms": 140,
    "p95_ms": 180,
    "p99_ms": 190,
    "iterations": 10,
    "total_ms": 1500
  },
  "metadata": {}
}
```

### Regression Detection

The benchmark system automatically compares current results with historical data. A regression is detected when:

- P95 latency increases by more than the threshold percentage (default: 10%)
- Average latency increases by more than the threshold percentage
- Maximum latency increases by more than the threshold percentage

The system generates a markdown report showing:

- Current results
- Last historical results
- Median of historical results
- Regression analysis with details

## Example Output

```
Starting benchmark...
Scenario directory: benchmark/scenarios
Iterations: 10
Warmup: 3
Threshold: 10.0%
Output directory: benchmark/results

Found 2 scenario(s)

Running benchmark: benchmark/scenarios/llm_latency.json
## Benchmark: llm_latency
- Iterations: 10
- Total time: 1500ms
- Min: 100ms
- Max: 200ms
- Avg: 150.0ms
- P50: 140ms
- P95: 180ms
- P99: 190ms

Results saved to benchmark/results/llm_latency

## Regression Report: llm_latency

### Current Results
## Benchmark: Current
- Iterations: 10
- Total time: 1500ms
- Min: 100ms
- Max: 200ms
- Avg: 150.0ms
- P50: 140ms
- P95: 180ms
- P99: 190ms

### Last Results
No previous results found

### Median Results
No historical results found

### Regression Analysis
- Threshold: 10.0%
- Regression detected: NO

Benchmark completed!
```

## Development

### Adding New Scenarios

1. Create a new JSON file in `benchmark/scenarios/`
2. Define the scenario with appropriate tool and parameters
3. Run the benchmark to test

### Extending the Framework

The benchmark framework is located in `test/benchmark/`:

- `benchmark_timer.mbt`: High-precision timing
- `benchmark_stats.mbt`: Statistical calculations
- `benchmark_scenario.mbt`: Scenario definitions
- `benchmark_runner.mbt`: Scenario execution
- `benchmark_persistence.mbt`: Result storage
- `benchmark_comparator.mbt`: Regression detection

### Testing

Run the benchmark tests:

```bash
moon test test/benchmark
```