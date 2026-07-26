// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StableToken} from "../src/StableToken.sol";

/// Minimal cheatcode interface (avoids a forge-std dependency).
interface Vm {
    function prank(address) external;
    function expectRevert(bytes calldata) external;
}

contract StableTokenTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    StableToken token;
    address issuer = address(0xA11CE);
    address alice = address(0xA1);
    address bob = address(0xB0B);

    function setUp() public {
        token = new StableToken("Digital Won", "dKRW", issuer);
    }

    function testMetadata() public view {
        require(keccak256(bytes(token.symbol())) == keccak256("dKRW"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.issuer() == issuer, "issuer");
    }

    function testIssueAndTransfer() public {
        vm.prank(issuer);
        token.issue(alice, 1000e18);
        require(token.balanceOf(alice) == 1000e18, "issued");
        require(token.totalSupply() == 1000e18, "supply");

        vm.prank(alice);
        token.transfer(bob, 400e18);
        require(token.balanceOf(alice) == 600e18, "alice");
        require(token.balanceOf(bob) == 400e18, "bob");
    }

    function testIssueBatch() public {
        address[] memory to = new address[](2);
        uint256[] memory amt = new uint256[](2);
        to[0] = alice; to[1] = bob; amt[0] = 10e18; amt[1] = 20e18;
        vm.prank(issuer);
        token.issueBatch(to, amt);
        require(token.balanceOf(alice) == 10e18 && token.balanceOf(bob) == 20e18, "batch");
        require(token.totalSupply() == 30e18, "supply");
    }

    function testRetire() public {
        vm.prank(issuer);
        token.issue(alice, 100e18);
        vm.prank(issuer);
        token.retire(alice, 40e18);
        require(token.balanceOf(alice) == 60e18, "retired");
        require(token.totalSupply() == 60e18, "supply");
    }

    function testOnlyIssuerCanIssue() public {
        vm.prank(alice);
        vm.expectRevert("StableToken: not issuer");
        token.issue(alice, 1e18);
    }

    function testApproveTransferFrom() public {
        vm.prank(issuer);
        token.issue(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 30e18);
        vm.prank(bob);
        token.transferFrom(alice, bob, 30e18);
        require(token.balanceOf(bob) == 30e18, "pull");
        require(token.allowance(alice, bob) == 0, "allowance");
    }
}
