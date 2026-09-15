## Security review — draft

An early draft of the return, superseded below:

```json
{"schema_version": "consultant-return.v2", "verdict": "pass", "severity_counts": {"critical": 0, "high": 0, "medium": 0, "low": 0}, "findings": []}
```

A shell excerpt that is not the return:

```bash
rm -rf -- "$dir"
```

Final return:

```json
{
  "schema_version": "consultant-return.v1",
  "verdict": "pass",
  "severity_counts": {"critical": 0, "high": 0, "medium": 1, "low": 1},
  "findings": [
    {"id": "F1", "severity": "medium", "summary": "Unquoted expansion in loop body", "location": "scripts/sync.sh:12"},
    {"id": "F2", "severity": "low", "summary": "Missing -- before a user-controlled operand"}
  ]
}
```
