pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/IBirbReferral.sol";

contract BirbReferral is IBirbReferral, Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    uint256 totalReferralCommissions = 0; // Total referral commissions
    mapping(address => bool) public operators;
    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => uint256) public referralCommissions; // referrer address => referral commissions per user

    event ReferralRecorded(address indexed user, address indexed referrer);
    event ReferralCommissionUpdated(
        address indexed referrer,
        uint256 commission,
        uint256 commissionSum,
        uint256 totalCommission
    );
    event OperatorUpdated(address indexed operator, bool indexed status);

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    function recordReferral(address _user, address _referrer)
        public
        override
        onlyOperator
    {
        if (
            _user != address(0) &&
            _referrer != address(0) &&
            _user != _referrer &&
            referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] = referralsCount[_referrer].add(1);
            emit ReferralRecorded(_user, _referrer);
        }
    }

    function recordReferralCommission(address _referrer, uint256 _commission)
        public
        override
        onlyOperator
    {
        if (_referrer != address(0) && _commission > 0) {
            referralCommissions[_referrer] = referralCommissions[_referrer].add(
                _commission
            );
            totalReferralCommissions = totalReferralCommissions.add(
                _commission
            );
            emit ReferralCommissionUpdated(
                _referrer,
                _commission,
                referralCommissions[_referrer],
                totalReferralCommissions
            );
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public override view returns (address) {
        return referrers[_user];
    }

    // Update the status of the operator
    function updateOperator(address _operator, bool _status)
        external
        onlyOwner
    {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }

    // Owner can drain tokens that are sent here by mistake
    function drainBEP20Token(
        IBEP20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }
}
