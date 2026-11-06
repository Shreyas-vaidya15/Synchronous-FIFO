### Parameter sweep

| Config | Result |
|---|---|
| depth 32, width 32 (default) | pass |
| depth 4, width 32 | pass |
| depth 8, width 32 | pass |
| depth 16, width 32 | pass |
| depth 64, width 32 | pass |
| depth 8, width 8 | pass |
| depth 6 | rejected by $error |
| depth 2 | rejected by $error |

### Mutation testing (current RTL, default config)

| Mutation | First failure | Caught by |
|---|---|---|
| remove ~full from do_write | t=450 | tb\tb.sv:100: 450: almost_full=1 expected 0 (occupancy 32) |
| remove ~empty from do_read | t=820 | tb\tb.sv:117: 820: read_data changed to 78dde6c4 without a valid read |
| full compares only lower pointer bits | t=30 | tb\tb.sv:92: 30: full=1 but model has 0 entries |
| remove ~full from almost_full | t=440 | tb\tb.sv:100: 440: almost_full=1 expected 0 (occupancy 32) |
| almost_empty uses < instead of <= | t=200 | tb\tb.sv:104: 200: almost_empty=0 expected 1 (occupancy 8) |
| difference one bit too narrow | t=440 | tb\tb.sv:104: 440: almost_empty=1 expected 0 (occupancy 32) |
| underflow = empty && read_en && write_en | t=820 | tb\tb.sv:65: 815: underflow=0 expected 1 (occupancy 0, read_en=1) |
| overflow = full && write_en && ~read_en | t=1190 | tb\tb.sv:60: 1185: overflow=0 expected 1 (occupancy 32, write_en=1) |
| write_ptr increments by 2 | t=90 | tb\tb.sv:112: 90: read_data=xxxxxxxx expected 3c6ef362 |
| no reset of read_data | t=30 | tb\tb.sv:117: 30: read_data changed to xxxxxxxx without a valid read |
