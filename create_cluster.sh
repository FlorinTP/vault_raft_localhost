#!/bin/bash 
#echo Default directories
export hash_padding="#############"
export a_workingdir="$(pwd)/vault" 
export a_basedir=$(basename "${a_workingdir}")
export a_maindir=$(dirname "${a_workingdir}")
export a_ifname='en0'
export a_vaultcnt=6
export a_ipaddr=$(ifconfig ${a_ifname}|grep 'broadcast'|awk '{print $2}')
export DEBUG=0
###
[ $DEBUG -gt 0 ] && ( echo -ne "${hash_padding}\nUsing: ${a_workingdir} as base ? (<Enter> for default path)"  && read a_ans )


### FUNCTION BLOCK
function create_vault_conf()
{
  echo "$hash_padding===${FUNCNAME[*]}==== "
  cd "${a_workingdir}/config" 

  # Create ALL the join blocks of the Vault Servers if a_vault_cnt is greater than 1
  >all_vault_servers.txt
  for i2_cnt in $(seq $a_vaultcnt) ; do
    icorrection=$(( $i2_cnt - 1 ))  
    port_i=$(( $icorrection * 10   + 8200 ))
    cat << EOFT1  > t_addon.txt 
        retry_join {
          leader_api_addr = "http://127.0.0.1:${port_i}"
        }
EOFT1
  [[ $i_cnt -gt 1 ]] && cat t_addon.txt >>all_vault_servers.txt
done

# Create transit seal block with the 127.0.0.1:8200 hardcoded for vault_1
cat << EOFT3 > t_addon.txt
seal "transit" {
   address            = "http://127.0.0.1:8200"
   disable_renewal    = "false"

   key_name           = "unseal_key"
   mount_path         = "transit/"
}
EOFT3

  rm -f config_?.hcl 2>/dev/null

  # Create each Vault server config file
  for i_cnt in $(seq 2 $a_vaultcnt) ; do
    icorrection=$(( $i_cnt - 1 ))  
    echo "Create final Vault server ${a_working_dir}/config/config_${i_cnt}.hcl"
    export port_i=$(( $icorrection * 10   + 8200 ))
    export port_iha=$(( $icorrection * 10  + 8201 ))
    mkdir -p "${a_workingdir}/data/vault_raft_${i_cnt}"
    cat << EOFT2 >  config_${i_cnt}.hcl 
ui = true
api_addr      = "http://127.0.0.1:${port_i}"
cluster_addr  = "http://127.0.0.1:${port_iha}"

listener "tcp" {
  address = "0.0.0.0:${port_i}"
  tls_disable = 1
}

storage "raft" {
        path = "${a_workingdir}/data/vault_raft_${i_cnt}"
        node_id = "vault_${i_cnt}"

        retry_join {
          leader_api_addr = "http://127.0.0.1:8210"
        }
EOFT2
    [ -s all_vault_servers.txt ] && cat all_vault_servers.txt >> config_${i_cnt}.hcl
    echo '}' >> config_${i_cnt}.hcl
    # Adding transit seal for all the configs except the first vault server
    #if [[ ${i_cnt} -gt 1 ]] ; then
    cat t_addon.txt >> config_${i_cnt}.hcl
    #fi
  done
  cat << EOFT4 > config_1.hcl
storage "inmem" {}

listener "tcp" {
   address = "127.0.0.1:8200"
   tls_disable = true
}

ui=true
disable_mlock = true
EOFT4
  return 0
}

function vault_cleanup()
{
  echo -ne "${hash_padding}Cleanup the vault logs and data files...\n"
  cd "${a_workingdir}/config"
  [ $? -eq 0 ] && rm t_addon.txt all_vault_servers.txt 2>/dev/null && find . -type f  -print -exec rm -rf -- {} \;
  cd "${a_workingdir}/data"
  if [ $? -eq 0 ] ; then
	 for tdir in $(ls) ; do
		 rm -rf -- "$tdir" && echo "rm $tdir" 
	 done;
  fi
  cd "${a_workingdir}/logs"
  if [ $? -eq 0 ] ; then
	 for tfile in $(ls vault* 2>/dev/null) ; do
		 rm -f -- "$tfile" && echo "rm $tfile" 
	 done;
  fi
  echo -ne "${hash_padding}Cleanup complete.${hash_padding}\n"
  return 0
}

function start_transit_vault()
{
  echo "$hash_padding===${FUNCNAME[*]}==== "
  cd ${a_workingdir}/config
  export VAULT_ADDR="http://127.0.0.1:8200" 
  export VAULT_LICENSE_PATH="${a_workingdir}/config/license.hclic"
  vault server -log-level=trace -config=./config_1.hcl 1>/dev/null 2>/dev/null&
  while : ; do
    vault status 1>/dev/null
    [ $? -eq 2 ] && break || sleep 1
  done
  vault status
  #export INIT_RESPONSE=$(vault operator init -format=json -key-shares 1 -key-threshold 1 )
  export INIT_RESPONSE=$(vault operator init -format=json -key-shares 1 -key-threshold 1 2>/dev/null)
  export UNSEAL_KEY=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64[0])
  export VAULT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r .root_token)

  echo "$UNSEAL_KEY" > unseal_key-vault_1
  echo "$VAULT_TOKEN" > root_token-vault_1

  vault operator unseal "$UNSEAL_KEY" > unseal_keys_vault_1.txt
  cat unseal_keys_vault_1.txt
  vault login "$VAULT_TOKEN"
  vault secrets enable transit
  vault write -f transit/keys/unseal_key
  echo "Successfully unsealed the First Vault Server used for Transit Key"
return 0
}

function start_vault()
{
  echo "$hash_padding===${FUNCNAME[*]}==== "
  cd "${a_workingdir}/config" || (echo "No configuration directoy!" ; return 1)

 for i_cnt in $(seq 2 ${a_vaultcnt} ) ; do
  echo " Starting Vault Server $i_cnt..."
  mkdir -p "${a_workingdir}/data/vault_${i_cnt}"
  local icorrection=$(( $i_cnt - 1 ))
  local port_i=$(( $icorrection * 10  + 8200 ))
  local port_iha=$(( $icorrection * 10  + 8201 ))
  export VAULT_ADDR="http://127.0.0.1:${port_i}" ; export ROOT_TOKEN=''
  export VAULT_LICENSE_PATH="${a_workingdir}/config/license.hclic"
  vault server -log-level=trace -config=./config_${i_cnt}.hcl 2>/dev/null 1>/dev/null &
  #vault server -log-level=trace -config=./config_${i_cnt}.hcl &
  set +x
  while : ; do
    vault status 1>/dev/null 2>/dev/null
    [ $? -eq 2 ] && break || sleep 1
  done
  [ $DEBUG -gt 0 ] && vault status
done
  return 0
}

function validate_vault()
{
  echo "$hash_padding===${FUNCNAME[*]}==== "
  cd ${a_workingdir}/config
  for i_cnt in $(seq 2 ${a_vaultcnt}) ; do
     local icorrection=$(( $i_cnt - 1 ))
     local port_i=$(( $icorrection * 10  + 8200 ))
     export VAULT_ADDR="http://127.0.0.1:${port_i}" 
     export INIT_RESPONSE=$(cat "root_token-vault_${i_cnt}")
     #export RECOVERY_KEY=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64[0])
     export VAULT_TOKEN=$(echo "$INIT_RESPONSE" )
     echo "${hash_padding}Testing the Vault Server Vault-${i_cnt} using Transit Key"
     vault login "$VAULT_TOKEN"
     vault secrets enable -path=kv kv-v2
     vault kv put kv/apikey webapp=testvalueinthefield
     sleep 1
     vault kv get kv/apikey
     vault secrets list
     vault kv get kv/apikey
     vault status
     vault operator raft list-peers
     echo "${hash_padding}Done testing"
  done
  cd ${a_workingdir}
  return 0
}

function unseal_vault()
{
  echo "$hash_padding===${FUNCNAME[*]}==== "
  cd ${a_workingdir}/config
  local i_node=2 ; local icorrection=$(( $i_node - 1)) 
  local port_i=$(( $icorrection * 10  + 8200 ))
  export VAULT_ADDR="http://127.0.0.1:${port_i}" 
  export INIT_RESPONSE=$(vault operator init -format=json -recovery-shares 1 -recovery-threshold 1 2>/dev/null )
  export RECOVERY_KEY=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64[0])
  export VAULT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r .root_token)
  echo "$RECOVERY_KEY" > "recovery_key-vault_${i_node}"
  echo "$VAULT_TOKEN" > "root_token-vault_${i_node}"
  echo "${hash_padding}Unsealed the Vault Server Vault-${i_node} using Transit Key"
  for i_cnt in $(seq 3 ${a_vaultcnt}) ; do
     #cp "root_token-vault_${i_node}" "root_token-vault_${i_cnt}"
     ln -s  "root_token-vault_${i_node}" "root_token-vault_${i_cnt}"
  done
  sleep 15
  [ $DEBUG -gt 0 ] && vault status
  return 0
  # No need to init others
  ##for i_cnt in $(seq 2 ${a_vaultcnt}) ; do
  ##   local icorrection=$(( $i_cnt - 1 ))
  ##   local port_i=$(( $icorrection * 10  + 8200 ))
  ##   export VAULT_ADDR="http://127.0.0.1:${port_i}" 
  ##   export INIT_RESPONSE=$(vault operator init -format=json -recovery-shares 1 -recovery-threshold 1 2>/dev/null )
  ##   export RECOVERY_KEY=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64[0])
  ##   export VAULT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r .root_token)
  ##   echo "$RECOVERY_KEY" > "recovery_key-vault_${i_cnt}"
  ##   echo "$VAULT_TOKEN" > "root_token-vault_${i_cnt}"
  ##   echo "${hash_padding}Unsealed the Vault Server Vault-${i_cnt} using Transit Key"
  ##   sleep 15
  ##   [ $DEBUG -gt 0 ] && vault status
  ##done
  ##return 0
}

function vault_ha_init()
{
  cd ${a_workingdir}/config
  for i_cnt in $(seq 3 ${a_vaultcnt}) ; do
     local icorrection=$(( $i_cnt - 1 ))
     local port_i=$(( $icorrection * 10  + 8200 ))
     export VAULT_ADDR="http://127.0.0.1:${port_i}" 
     export VAULT_JOIN_ADDR="http://127.0.0.1:8210}" 
     export INIT_RESPONSE=$(cat "root_token-vault_${i_cnt}")
     export VAULT_TOKEN=$(echo "$INIT_RESPONSE")
     echo "Vault Server vault-${i_cnt} Joining the Vault Server Vault-${icorrection}"
     vault login "$VAULT_TOKEN"
     vault operator raft list-peers
     #vault operator raft join "$VAULT_JOIN_ADDR"
     echo "${hash_padding}Cluster formation done."
  done
  cd ${a_workingdir}
  return 0
}


### MAIN BODY
if [ -d "${a_workingdir}" ] ; then
  echo "Directory already present. Cleanup and re-execute the script."
  cd "${a_maindir}" && rm -rf "${a_basedir}"
  exit 1
else
  echo "Using ${a_maindir} and ${a_basedir}"
  cd "${a_maindir}" 
  mkdir -p "${a_workingdir}/logs"
  mkdir -p "${a_workingdir}/config"
  mkdir -p "${a_workingdir}/data"
  chmod 0755 "${a_workingdir}/data"
fi

create_vault_conf 
start_transit_vault
start_vault
unseal_vault
vault_ha_init
validate_vault
read x
[ $DEBUG -gt 0 ] && ( echo -ne "${hash_padding}\nTesting and validation OK? (<Enter> for ending thje script)"  && read a_ans )
echo -ne  "\n${hash_padding}Done.\n"
killall vault
vault_cleanup


