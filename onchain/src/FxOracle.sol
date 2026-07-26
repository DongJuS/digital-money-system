// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FxOracle
/// @notice Stores an off-chain FX reference rate (e.g. USD/KRW) published by an `updater`
///         (the institution, like a central bank publishing a reference rate).
///         No funds are held; an off-chain relayer reads a public FX API and pushes the rate.
contract FxOracle {
    /// @notice Authorized to push new rates.
    address public updater;

    /// @notice The currency pair, e.g. "USD/KRW".
    string public pair;

    /// @notice Number of decimals the rate is scaled by (1e8).
    uint8 public constant decimals = 8;

    /// @notice Latest rate, scaled by 1e8. e.g. USD/KRW = 1350.12 -> 135012000000.
    uint256 public rate;

    /// @notice Block timestamp of the last update.
    uint256 public updatedAt;

    event RateUpdated(uint256 rate, uint256 timestamp);
    event UpdaterTransferred(address indexed from, address indexed to);

    modifier onlyUpdater() {
        require(msg.sender == updater, "FxOracle: not updater");
        _;
    }

    constructor(string memory _pair, address _updater) {
        require(_updater != address(0), "FxOracle: zero updater");
        pair = _pair;
        updater = _updater;
        emit UpdaterTransferred(address(0), _updater);
    }

    /// @notice Publish a new reference rate (institution only).
    function setRate(uint256 _rate) external onlyUpdater {
        require(_rate > 0, "FxOracle: zero rate");
        rate = _rate;
        updatedAt = block.timestamp;
        emit RateUpdated(_rate, block.timestamp);
    }

    /// @notice Latest rate + timestamp (Chainlink-ish reader).
    function latestRate() external view returns (uint256 _rate, uint256 _updatedAt) {
        return (rate, updatedAt);
    }

    /// @notice Convert a token amount (18 decimals) into the quote currency using the rate.
    ///         e.g. amount of a USD-referenced coin -> KRW value.
    function convert(uint256 amount18) external view returns (uint256) {
        return (amount18 * rate) / 1e8;
    }

    /// @notice True if the rate is older than `maxAge` seconds (staleness guard).
    function isStale(uint256 maxAge) external view returns (bool) {
        if (updatedAt == 0) return true;
        return block.timestamp - updatedAt > maxAge;
    }

    function transferUpdater(address to) external onlyUpdater {
        require(to != address(0), "FxOracle: zero to");
        emit UpdaterTransferred(updater, to);
        updater = to;
    }
}
