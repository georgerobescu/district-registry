(ns district-registry.shared.smart-contracts) 

(def smart-contracts 
{:district-factory
 {:name "DistrictFactory",
  :address "0xf3f97557961ea666711d96e8048526aa8e91611c"},
 :ds-guard
 {:name "DSGuard",
  :address "0x9e7fc6692ce19980209a06228b5fc4f2a3f571d1"},
 :param-change-registry
 {:name "ParamChangeRegistry",
  :address "0xa7b49972ff554718cfa65981548c23e68387c4fb"},
 :DNT
 {:name "District0xNetworkToken",
  :address "0x6736a60d75eec3e7c9d7055fa7f48da17df4ed9a"},
 :param-change-registry-db
 {:name "EternalDb",
  :address "0x0e9b3a0d7e8f9d06d419930e28b57664f2eb2f86"},
 :param-change
 {:name "ParamChange",
  :address "0x6bf93b1e408bf2807a09611daccbcf96ea0c7fc2"},
 :district-registry
 {:name "Registry",
  :address "0x6d4cd59192581eeee0071f3cfacada53e95bfbd6"},
 :minime-token-factory
 {:name "MiniMeTokenFactory",
  :address "0xbe7737ebb2c43b736bf10f781744b0725769ad9e"},
 :param-change-factory
 {:name "ParamChangeFactory",
  :address "0x2170d6b31b399af3a9d0fcadc5cc6f843a6ec759"},
 :param-change-registry-fwd
 {:name "MutableForwarder",
  :address "0xc352d21257eb1b5490982ce1998f7d8e1ddc2c41"},
 :district-registry-db
 {:name "EternalDb",
  :address "0x8fa336f5b9ff1b49e55427a6e62826aa9769e18d"},
 :district-registry-fwd
 {:name "MutableForwarder",
  :address "0x71f27d61cca0b82c7c1096736d1f92e830e41225"},
 :district
 {:name "District",
  :address "0xc857fc9d383933e1baddcb354954072e609ff559"}})