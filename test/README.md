# Ecosystem Coordination Tests
## Forge tests
### Unit tests
- validation tests:
```bash
make tests
```
- validation tests with gas report:
```bash
make test-with-gas-report
```

### Invariant tests
#### Configuration
Invariant test scenarios can be externally configured by customizing following environment variables:
| Variable | Default | Description |
| ------------- | ------------- | ------------- |
| NUM_ACTORS  | 20 | Max number of actors to participate in invariant testing |
| NUM_PROPOSALS  | 200 | Max number of proposals that can be proposed in invariant testing |
| LOGS_VERBOSITY | 0 | <p> Details to log <p> 0 = No Logs <p> 1 =  Calls details, Proposal details, Time details <p> 2 = Calls details, Proposal details, Time details, Funding proposal details, Finalize proposals details <p> 3 = Calls details, Proposal details, Time details, Funding proposal details, Finalize proposals details, Actor details

#### Custom Scenarios

Custom scenario configurations are defined in [scenarios](forge/invariants/scenarios/) directory.
For running a custom scenario
```bash
make test-invariant SCENARIO=<custom-pool>
```
For example, to test all invariants for multiple distribution (Roll between each handler call can be max 5000 blocks):
```bash
make test-invariant SCENARIO=MultipleDistribution
```

#### Commands
- run all invariant tests:
```bash
make test-invariant-all
```

### Code Coverage
- generate basic code coverage report:
```bash
make coverage
```
- exclude tests from code coverage report:
```
apt-get install lcov
bash ../check-code-coverage.sh
```
