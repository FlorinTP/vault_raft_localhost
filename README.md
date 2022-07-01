# vault_raft_localhost

The repository is used for creating a test Vault+Raft Integrated storage playground.
The script is written in Bash and was successfully tested on MAC (Intel and M1).


Prerequisites
Install the latest version of vault and bash for your distribution.
As example for MAC, using brew:
brew install vault
brew install bash


Running the Vault HA Cluster with Raft integrated storage involves the following block actions:
1 - validating the environment
2 - creating the transit Vault server
3 - start and unseal the first Vault Server used as transit for unsealing key
4 - Create the unseal transit key
5 - Create Vault configuration files,in a dynamic way, cluster nodes (n-1) by specifying the variable
a_vaultcnt=4
(default if 4 Vault servers, one transit "in memory" server and 3 Vault servers running in a HA Cluster and having as Raft as storage backed).
6 - Recover the shared key from initialization from transit Vaul and create a temporary store of VAULT_TOKEN (only for testing purposes)
7 - Enable a secret engine type KV in the path kv of version kv-v2
8 - Store a secret into apikey with field webapp=testvalueinthefield.
 

How to create the Vaul HA Cluster
Clone the current repository or only the current script create_cluster.sh
If the vault directory is present then a cleanu-up is needed.
In this scenario the script is singaling the vault directory, delete the vault directory and exit.

At the next execution the script is executing the block actions.

For test purpose, the variable DEBUG may be set to a value greater than "0".
This will allow the validation and the test scenarios.
The script create_cluster.sh will wait for a confirmation before cleanup.

