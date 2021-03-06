pragma solidity ^0.4.18;

import "ownership/Ownable.sol";
import "token/minime/MiniMeToken.sol";
import "./StakeBankInterface.sol";
import "math/SafeMath.sol";

contract StakeBank is StakeBankInterface {

    using SafeMath for uint256;

    struct StakeBankCheckpoint {
        uint256 at;
        uint256 amount;
    }

    MiniMeToken public token;

    StakeBankCheckpoint[] public stakeHistory;

    mapping (address => StakeBankCheckpoint[]) public stakesFor;

    /// @param _token Token that can be staked.
    function constructStakeBank(MiniMeToken _token) internal {
        require(address(_token) != 0x0);
        token = _token;   
    }

    /// @notice Stakes a certain amount of tokens.
    /// @param amount Amount of tokens to stake.
    /// @param data Data field used for signalling in more complex staking applications.
    function stake(uint256 amount, bytes data) public {
        stakeFor(msg.sender, amount, data);
    }

    /// @notice Stakes a certain amount of tokens for another user.
    /// @param user Address of the user to stake for.
    /// @param amount Amount of tokens to stake.
    /// @param data Data field used for signalling in more complex staking applications.
    function stakeFor(address user, uint256 amount, bytes data) public {
        updateStakeBankCheckpointAtNow(stakesFor[user], amount, false);
        updateStakeBankCheckpointAtNow(stakeHistory, amount, false);

        require(token.transferFrom(tx.origin, address(this), amount));
        // require(token.transferFrom(msg.sender, address(this), amount));
        // The line above is the original StakeBank implementation, but we changed
        // `msg.sender` to `tx.origin` so that it works with `approveAndCall`.

        Staked(user, amount, totalStakedFor(user), data);
    }

    /// @notice Unstakes a certain amount of tokens.
    /// @param amount Amount of tokens to unstake.
    /// @param data Data field used for signalling in more complex staking applications.
    function unstake(uint256 amount, bytes data) public {
        require(totalStakedFor(msg.sender) >= amount);

        updateStakeBankCheckpointAtNow(stakesFor[msg.sender], amount, true);
        updateStakeBankCheckpointAtNow(stakeHistory, amount, true);

        require(token.transfer(msg.sender, amount));
        Unstaked(msg.sender, amount, totalStakedFor(msg.sender), data);
    }

    /// @notice Returns total tokens staked for address.
    /// @param addr Address to check.
    /// @return amount of tokens staked.
    function totalStakedFor(address addr) public view returns (uint256) {
        StakeBankCheckpoint[] storage stakes = stakesFor[addr];

        if (stakes.length == 0) {
            return 0;
        }

        return stakes[stakes.length-1].amount;
    }

    /// @notice Returns total tokens staked.
    /// @return amount of tokens staked.
    function totalStaked() public view returns (uint256) {
        return totalStakedAt(block.number);
    }

    /// @notice Returns if history related functions are implemented.
    /// @return Bool whether history is implemented.
    function supportsHistory() public pure returns (bool) {
        return true;
    }
    
    /// @notice Returns the token address.
    /// @return Address of token.
    function token() public view returns (address) {
        return token;
    }

    /// @notice Returns last block address staked at.
    /// @param addr Address to check.
    /// @return block number of last stake.
    function lastStakedFor(address addr) public view returns (uint256) {
        StakeBankCheckpoint[] storage stakes = stakesFor[addr];

        if (stakes.length == 0) {
            return 0;
        }

        return stakes[stakes.length-1].at;
    }

    /// @notice Returns total amount of tokens staked at block for address.
    /// @param addr Address to check.
    /// @param blockNumber Block number to check.
    /// @return amount of tokens staked.
    function totalStakedForAt(address addr, uint256 blockNumber) public view returns (uint256) {
        return stakedAt(stakesFor[addr], blockNumber);
    }

    /// @notice Returns the total tokens staked at block.
    /// @param blockNumber Block number to check.
    /// @return amount of tokens staked.
    function totalStakedAt(uint256 blockNumber) public view returns (uint256) {
        return stakedAt(stakeHistory, blockNumber);
    }

    function updateStakeBankCheckpointAtNow(StakeBankCheckpoint[] storage history, uint256 amount, bool isUnstake) internal {

        uint256 length = history.length;
        if (length == 0) {
            history.push(StakeBankCheckpoint({at: block.number, amount: amount}));
            return;
        }

        if (history[length-1].at < block.number) {
            history.push(StakeBankCheckpoint({at: block.number, amount: history[length-1].amount}));
        }

        StakeBankCheckpoint storage checkpoint = history[length];

        if (isUnstake) {
            checkpoint.amount = checkpoint.amount.sub(amount);
        } else {
            checkpoint.amount = checkpoint.amount.add(amount);
        }
    }

    function stakedAt(StakeBankCheckpoint[] storage history, uint256 blockNumber) internal view returns (uint256) {
        uint256 length = history.length;

        if (length == 0 || blockNumber < history[0].at) {
            return 0;
        }

        if (blockNumber >= history[length-1].at) {
            return history[length-1].amount;
        }

        uint min = 0;
        uint max = length-1;
        while (max > min) {
            uint mid = (max + min + 1) / 2;
            if (history[mid].at <= blockNumber) {
                min = mid;
            } else {
                max = mid-1;
            }
        }

        return history[min].amount;
    }
}
