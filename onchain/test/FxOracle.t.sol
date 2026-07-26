// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FxOracle} from "../src/FxOracle.sol";

interface Vm {
    function prank(address) external;
    function expectRevert(bytes calldata) external;
    function warp(uint256) external;
}

contract FxOracleTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    FxOracle oracle;
    address updater = address(0x11DA7E);

    function setUp() public {
        oracle = new FxOracle("USD/KRW", updater);
    }

    function testSetRateAndConvert() public {
        // 1 USD = 1350.12 KRW -> scaled by 1e8
        vm.prank(updater);
        oracle.setRate(135012000000);
        (uint256 r, uint256 t) = oracle.latestRate();
        require(r == 135012000000 && t > 0, "rate");
        // 10 USD-referenced coins -> KRW = 10 * 1350.12 = 13501.2 (18 decimals)
        require(oracle.convert(10e18) == 13501_200000000000000000, "convert");
    }

    function testConvertMath() public {
        vm.prank(updater);
        oracle.setRate(135000000000); // 1350.00
        // 2e18 units * 1350 = 2700e18
        require(oracle.convert(2e18) == 2700e18, "krw value");
    }

    function testOnlyUpdater() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("FxOracle: not updater");
        oracle.setRate(1);
    }

    function testStaleness() public {
        require(oracle.isStale(60), "fresh-before-set stale");
        vm.prank(updater);
        oracle.setRate(135000000000);
        require(!oracle.isStale(60), "fresh");
        vm.warp(block.timestamp + 120);
        require(oracle.isStale(60), "stale");
    }

    function testRejectZeroRate() public {
        vm.prank(updater);
        vm.expectRevert("FxOracle: zero rate");
        oracle.setRate(0);
    }
}
