//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PhoneTransfer is Ownable {
    using Counters for Counters.Counter;
    struct Payment {
        address sender;
        address receiver;
        IERC20 token;
        uint amount;
        uint Unique_ID;
        uint date;
    }

    struct EscrowPayment {
        address sender;
        string unregisteredReceiver;
        address receiver;
        IERC20 token;
        uint amount;
        uint Unique_ID;
        uint date;
    }

    enum Action {
        CANCEL,
        ACCEPT,
        REJECT,
        CLAIM
    }

    event prePaymentEve(
        uint transactionNo,
        address indexed sender,
        address indexed receiver,
        IERC20 token,
        uint amount,
        uint date
    );

    event postPaymentEve(
        uint transactionNo,
        address indexed sender,
        address indexed receiver,
        IERC20 token,
        uint amount,
        uint date
    );

    event requestPaymentEve(
        uint transactionNo,
        address indexed requestedBy,
        address indexed requestedFrom,
        IERC20 token,
        uint amount,
        uint date
    );

    event fullfillRequestPaymentEve(
        uint transactionNo,
        address indexed requestedBy,
        address indexed requestedFrom,
        uint status,
        uint date
    );

    event escrowPaymentEve(
        uint transactionNo,
        address indexed sender,
        string indexed receiver,
        IERC20 token,
        uint amount,
        uint date
    );

    event fullfillEscrowPaymentEve(
        uint transactionNo,
        address indexed sender,
        string indexed receiver,
        address receiverAdress,
        uint status,
        uint date
    );

    Counters.Counter uniqueTransactionNo;
    mapping(uint => Payment) requestedPayments;
    mapping(uint => EscrowPayment) unregisteredEscrowPayments;
    mapping(address => mapping(address => uint)) escrowedBalances;
    mapping(uint => string) multiChainContractAddress;
    mapping(uint => string) chainIDResolver;


    function updateMultiChainContractAddress(
        uint chainID,
        string memory contractAddress
    ) public onlyOwner {
        multiChainContractAddress[chainID] = contractAddress;
    }

    /*
    /Normal transfers will only show successful transactions for now (Will check the feasibility of showing failed transfers later)
    */
    function transferTokens(
        address to,
        address tokenAddr,
        uint256 amount
    ) public {
        Payment memory directTransfer = Payment(
            msg.sender,
            to,
            IERC20(tokenAddr),
            amount,
            uniqueTransactionNo.current(),
            block.timestamp
        );
        uniqueTransactionNo.increment();
        /*emit prePaymentEve
        (
            directTransfer.Unique_ID, 
            directTransfer.sender, 
            directTransfer.receiver, 
            directTransfer.token, 
            directTransfer.amount,
            false,
            block.timestamp
        );*/
        require(
            IERC20(tokenAddr).allowance(msg.sender, address(this)) >= amount,
            "TokenTransfer: Not enough allowance"
        );
        IERC20(tokenAddr).transferFrom(msg.sender, to, amount);
        emit postPaymentEve(
            directTransfer.Unique_ID,
            directTransfer.sender,
            directTransfer.receiver,
            directTransfer.token,
            directTransfer.amount,
            block.timestamp
        );
    }

    function requestPayment(
        address requestedFrom,
        address tokenAddr,
        uint amount
    ) public {
        Payment memory directTransfer = Payment(
            requestedFrom,
            msg.sender,
            IERC20(tokenAddr),
            amount,
            uniqueTransactionNo.current(),
            block.timestamp
        );
        uniqueTransactionNo.increment();
        requestedPayments[directTransfer.Unique_ID] = directTransfer;
        emit requestPaymentEve(
            directTransfer.Unique_ID,
            msg.sender,
            requestedFrom,
            directTransfer.token,
            amount,
            block.timestamp
        );
    }

    /*
        Additional Feature: Should support offchain signing(EIP-2612 & EIP-712)
        The sender is the entity from whom the payment request is made. 
        The receiver is the entity that initiates the payment request.
        If A requested 50USDT from B, then B is the sender and A is the receiver.
    */
    function fullFillRequestPayment(uint transactionNo, uint status) public {
        Payment storage pendingPayment = requestedPayments[transactionNo];
        require(
            msg.sender == pendingPayment.sender ||
                msg.sender == pendingPayment.receiver,
            "Unauthorized."
        );
        require(
            status <= uint(Action.REJECT) &&
                ((msg.sender == pendingPayment.sender &&
                    status >= uint(Action.ACCEPT)) ||
                    (msg.sender == pendingPayment.receiver &&
                        status == uint(Action.CANCEL))),
            "Invalid Status selected."
        );

        if (status == 1) {
            require(
                (pendingPayment.token).allowance(
                    pendingPayment.sender,
                    address(this)
                ) >= pendingPayment.amount,
                "TokenTransfer: Not enough allowance"
            );
            pendingPayment.token.transferFrom(
                pendingPayment.sender,
                pendingPayment.receiver,
                pendingPayment.amount
            );
        }
        emit fullfillRequestPaymentEve(
            pendingPayment.Unique_ID,
            pendingPayment.receiver,
            pendingPayment.sender,
            status,
            block.timestamp
        );
        delete requestedPayments[transactionNo];
    }

    /*
        unregisteredReceiver: represents the hash of encrypted user's phone number
     */
    function sendEcrowPayment(
        string memory unregisteredReceiver,
        address token,
        uint amount
    ) public {
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "TokenTransfer: Not enough allowance"
        );
        EscrowPayment memory payment = EscrowPayment(
            msg.sender,
            unregisteredReceiver,
            address(0),
            IERC20(token),
            amount,
            uniqueTransactionNo.current(),
            block.timestamp
        );
        uniqueTransactionNo.increment();
        unregisteredEscrowPayments[payment.Unique_ID] = payment;
        payment.token.transferFrom(msg.sender, address(this), amount);
        escrowedBalances[token][msg.sender] += amount;
        emit escrowPaymentEve(
            payment.Unique_ID,
            payment.sender,
            payment.unregisteredReceiver,
            payment.token,
            payment.amount,
            block.timestamp
        );
    }

    function fullFillEscrowPayment(uint transactionNo, Action status) public {
        EscrowPayment memory payment = unregisteredEscrowPayments[
            transactionNo
        ];
        require(
            (((payment.sender == msg.sender && status == Action.CANCEL) ||
              (payment.receiver == msg.sender && status == Action.CLAIM))),
            "Unauthorized"
        );
        require(
            escrowedBalances[address(payment.token)][msg.sender] >=
                payment.amount,
            "Insufficient balance"
        );
        require(
            status == Action.CLAIM || status == Action.CANCEL,
            "Invalid status requested"
        );

        escrowedBalances[address(payment.token)][msg.sender] -= payment.amount;
        payment.token.transfer(msg.sender, payment.amount);
        delete unregisteredEscrowPayments[transactionNo];
        emit fullfillEscrowPaymentEve(
            transactionNo,
            payment.sender,
            payment.unregisteredReceiver,
            payment.receiver,
            uint(status),
            block.timestamp
        );
    }

    function resolvePhonetoPublicAddress(
        uint transactionNo,
        string memory unregisteredReceiver,
        address updatePubKeyOfUnregisteredReceiver
    ) public onlyOwner {
        EscrowPayment storage payment = unregisteredEscrowPayments[
            transactionNo
        ];
        require(
            payment.receiver == address(0),
            "Escrow payment ownership is already changed"
        );
        bytes32 unregisteredReceiverHash = keccak256(
            abi.encodePacked(unregisteredReceiver)
        );
        bytes32 paymentUnregisteredReceiverHash = keccak256(
            abi.encodePacked(payment.unregisteredReceiver)
        );

        require(
            unregisteredReceiverHash == paymentUnregisteredReceiverHash,
            "Receiver doesn't match"
        );
        require(
            escrowedBalances[address(payment.token)][payment.sender] >=
                payment.amount,
            "Not enough balance in the sender account"
        );

        payment.receiver = updatePubKeyOfUnregisteredReceiver;
        escrowedBalances[address(payment.token)][payment.sender] -= payment
            .amount;
        escrowedBalances[address(payment.token)][
            updatePubKeyOfUnregisteredReceiver
        ] += payment.amount;
    }
}
