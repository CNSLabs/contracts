forge script script/1_DeployCNSTokenL1.s.sol:DeployCNSTokenL1 --rpc-url sepolia --broadcast --verify

forge script script/2_DeployCNSTokenL2.s.sol:DeployCNSTokenL2 --rpc-url linea_sepolia --broadcast --verify

forge script script/3_UpgradeCNSTokenL2ToV2.s.sol:UpgradeCNSTokenL2ToV2 --rpc-url linea_sepolia --broadcast --verify

forge script script/DemoV2Features.s.sol:DemoV2Features --rpc-url linea_sepolia  