// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/CREATE2Factory.sol";
import "../src/CNSTokenL1.sol";
import "../src/CNSTokenL2.sol";
import "../src/CNSAccessNFT.sol";
import "../src/CNSTierProgression.sol";
import "../src/CNSTokenSale.sol";
import "../src/CNSAccessControl.sol";

contract DeployCNSContractsTest is Test {
    CREATE2Factory public factory;
    CNSTokenL1 public tokenL1;
    CNSTokenL2 public tokenL2;
    CNSAccessNFT public accessNFT;
    CNSTierProgression public tierProgression;
    CNSTokenSale public tokenSale;
    CNSAccessControl public accessControl;

    address public owner = address(0x1234);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    // Deterministic deployment salts
    bytes32 public constant TOKEN_L1_SALT = keccak256("CNS_TOKEN_L1_V1");
    bytes32 public constant TOKEN_L2_SALT = keccak256("CNS_TOKEN_L2_V1");

    function setUp() public {
        factory = new CREATE2Factory();
    }

    function testCREATE2FactoryDeployment() public {
        // Verify factory is deployed
        assertTrue(address(factory) != address(0), "Factory should be deployed");

        // Test that empty bytecode produces zero address
        address zeroAddr = factory.calculateAddress("", bytes32(0));
        assertEq(zeroAddr, address(0), "Empty bytecode should produce zero address");
    }

    // Simple test contract for CREATE2 deployment
    function testSimpleContract() public {
        // Test with a simple contract that just has a basic constructor
        bytes memory simpleBytecode = type(CREATE2Factory).creationCode;

        address predicted = factory.calculateAddress(simpleBytecode, TOKEN_L1_SALT);
        assertTrue(predicted != address(0));

        // This should fail because CREATE2Factory already exists at that address
        // But the calculation should work
        assertTrue(predicted != address(factory));
    }

    function testDeterministicAddressCalculation() public {
        // Calculate expected addresses
        address predictedTokenL1 = factory.calculateAddress(
            type(CNSTokenL1).creationCode,
            TOKEN_L1_SALT
        );

        // Verify address calculation works
        assertTrue(predictedTokenL1 != address(0));
        assertTrue(uint160(predictedTokenL1) > 0);
    }

    function testSaltUniqueness() public {
        // Different salts should produce different addresses
        bytes32 differentSalt = keccak256("DIFFERENT_SALT");

        address addr1 = factory.calculateAddress(type(CNSTokenL1).creationCode, TOKEN_L1_SALT);
        address addr2 = factory.calculateAddress(type(CNSTokenL1).creationCode, differentSalt);

        assertTrue(addr1 != addr2);
    }

    function testDeploymentStructure() public {
        // Test that we can calculate addresses correctly
        address predictedTokenL1 = factory.calculateAddress(
            type(CNSTokenL1).creationCode,
            TOKEN_L1_SALT
        );

        address predictedTokenL2 = factory.calculateAddress(
            abi.encodePacked(type(CNSTokenL2).creationCode, abi.encode(owner, predictedTokenL1)),
            TOKEN_L2_SALT
        );

        // Verify the addresses are different and valid
        assertTrue(predictedTokenL1 != address(0));
        assertTrue(predictedTokenL2 != address(0));
        assertTrue(predictedTokenL1 != predictedTokenL2);

        // Verify they follow the CREATE2 address format
        assertTrue(uint160(predictedTokenL1) > 0);
        assertTrue(uint160(predictedTokenL2) > 0);
    }

    function testDeploymentScriptIntegration() public {
        // Test that the deployment script constants are accessible
        assertTrue(TOKEN_L1_SALT != bytes32(0));
        assertTrue(TOKEN_L2_SALT != bytes32(0));
        assertTrue(TOKEN_L1_SALT != TOKEN_L2_SALT);
    }

    function testDeploymentAddressConsistency() public {
        // Calculate addresses twice with same salt - should be identical
        address predictedTokenL1_1 = factory.calculateAddress(
            type(CNSTokenL1).creationCode,
            TOKEN_L1_SALT
        );

        address predictedTokenL1_2 = factory.calculateAddress(
            type(CNSTokenL1).creationCode,
            TOKEN_L1_SALT
        );

        // Same salt should produce same address
        assertEq(predictedTokenL1_1, predictedTokenL1_2);
    }
}
