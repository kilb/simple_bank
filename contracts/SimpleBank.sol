pragma solidity ^0.5.8;

contract SimpleBank {
    struct Bank {
        string name;
        uint balance;
        uint deposit_rate;
        uint loan_rate;
        mapping (address => Record) deposit_records;
        mapping (address => Record) loan_records;
        address[] accounts;
        bool isUsed;
    }
    struct Record {
        uint start;
        uint amount;
        bool isUsed;
    }
    struct Action {
        uint date;
        address bank_from;
        address bank_to;
        uint amount;
    }
    // the registered banks
    mapping (address => Bank) private banks;
    // banks borrow money from the central bank
    mapping (address => Record) loan_records;
    // banks lend money each other.
    Action[] private actions;
    address[] private bank_accounts;

    uint256 private max_deposit_rate;
    uint256 private max_loan_rate;

    address public owner;
    
    constructor() public {
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        max_deposit_rate = 5;
        max_loan_rate = 5;
    }

    /// @notice register the bank
    /// @return The balance remaining for the bank
    function register(string memory bank_name, uint deposit_rate, uint loan_rate) public returns (uint) {
        require(!banks[msg.sender].isUsed,"You have been registered!");
        require(loan_rate <= max_loan_rate && deposit_rate <= max_deposit_rate,"Wrong rate!");
        address[] memory accounts = new address[](1);

        banks[msg.sender] = Bank(bank_name, 10000000000, deposit_rate, loan_rate, accounts, true);
        bank_accounts[bank_accounts.length++] = msg.sender;

        return banks[msg.sender].balance;
    }

    /// @notice Deposit money into bank
    /// @return The balance of the user after the deposit is made
    function deposit(uint amount, address bank) public returns (uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        uint64 bn = uint64(block.number);
        if(banks[bank].deposit_records[msg.sender].isUsed) {
           Record memory r = banks[bank].deposit_records[msg.sender];
           // the new amount
           uint new_amount = (((bn-r.start) * banks[bank].deposit_rate * r.amount) / 1000) + r.amount + amount;
           r.start = bn;
           r.amount = new_amount;
           banks[bank].deposit_records[msg.sender] = r;
        } else {
           banks[bank].deposit_records[msg.sender] = Record(bn, amount, true);
           // add account
           if(!banks[bank].loan_records[msg.sender].isUsed) {
              banks[bank].accounts[banks[bank].accounts.length++] = msg.sender;
           }
        }
        // TODO: make it more accurate
        banks[bank].balance += amount;
        return banks[bank].deposit_records[msg.sender].amount;
    }

    /// @notice Borrow money into bank
    /// @return The loan balance of the user after the loan is made
    function borrow(uint amount, address bank) public returns (uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        require(banks[bank].balance > amount, "No enough money");
        uint bn = block.number;
        if(banks[bank].loan_records[msg.sender].isUsed) {
           Record memory r = banks[bank].loan_records[msg.sender];
           // the new amount
           uint new_amount = (((bn-r.start) * banks[bank].loan_rate * r.amount) / 1000) + r.amount + amount;
           r.start = bn;
           r.amount = new_amount;
           banks[bank].loan_records[msg.sender] = r;
        } else {
           banks[bank].loan_records[msg.sender] = Record(bn, amount, true);
           // add account
           if(!banks[bank].deposit_records[msg.sender].isUsed) {
              banks[bank].accounts[banks[bank].accounts.length++] = msg.sender;
           }
        }
        // TODO: make it more accurate
        banks[bank].balance -= amount;
        return banks[bank].loan_records[msg.sender].amount;
    }

    /// @notice withdraw money from bank
    /// @return The balance of the user after the withdraw is made
    function withdraw(uint amount, address bank) public returns (uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        require(banks[bank].deposit_records[msg.sender].isUsed, "You have no deposit in this bank");
        require(banks[bank].balance > amount, "No enough money in bank");

        Record memory r = banks[bank].deposit_records[msg.sender];
        uint bn = block.number;
        // the new amount
        uint new_amount = (((bn-r.start) * banks[bank].deposit_rate * r.amount) / 1000) + r.amount;
        r.start = bn;
        r.amount = new_amount;
        require(r.amount > amount, "You have no enough money!");
        r.amount -= amount;
        banks[bank].deposit_records[msg.sender] = r;
        // TODO: make it more accurate
        banks[bank].balance -= amount;
        return banks[bank].deposit_records[msg.sender].amount;
    }

    /// @notice repay money to bank
    /// @return The balance of the user after the repay is made
    function repay(uint amount, address bank) public returns (uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        require(banks[bank].loan_records[msg.sender].isUsed, "You have no deposit in this bank");

        Record memory r = banks[bank].loan_records[msg.sender];
        uint bn = block.number;
        // the new amount
        uint new_amount = (((bn-r.start) * banks[bank].loan_rate * r.amount) / 1000) + r.amount;
        r.start = bn;
        r.amount = new_amount;
        require(r.amount > amount, "You pay too much!");
        r.amount -= amount;
        banks[bank].loan_records[msg.sender] = r;
        // TODO: make it more accurate
        banks[bank].balance += amount;
        return banks[bank].loan_records[msg.sender].amount;
    }

    /// @notice Bank borrow money from central bank
    /// @return The total balance of the bank after the borrow is made
    function borrow_from_central(uint amount) public returns (uint) {
        require(banks[msg.sender].isUsed, "Bank is not registered");
        banks[msg.sender].balance += amount;
        loan_records[msg.sender].amount += amount;

        return banks[msg.sender].balance;
    }

    /// @notice Bank borrow money from bank
    /// @return The total balance of the bank after the borrow is made
    function borrow_from_bank(uint amount, address bank) public returns (uint, uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        require(banks[msg.sender].isUsed, "You are not registered");
        require(banks[bank].balance > amount, "No enough money");

        banks[msg.sender].balance += amount;
        banks[bank].balance -= amount;
        actions[actions.length++] = Action(block.number, bank, msg.sender, amount);

        return (banks[msg.sender].balance, banks[msg.sender].balance);
    }

    /// @notice bank update the rate
    /// @return the new rate
    function update_rate(uint deposit_rate, uint loan_rate) public returns (uint, uint) {
        require(banks[msg.sender].isUsed, "Bank is not registered");
        require(loan_rate <= max_loan_rate && deposit_rate <= max_deposit_rate,"Wrong rate!");
        uint bn = block.number;
        // the rate changed, so we should calculate the amount
        uint n = banks[msg.sender].accounts.length;
        for (uint i = 0; i<n; i++) {
            address k = banks[msg.sender].accounts[i];

            if(banks[msg.sender].deposit_records[k].isUsed) {
                Record memory r = banks[msg.sender].deposit_records[k];
                uint new_amount = (((bn-r.start) * banks[msg.sender].deposit_rate * r.amount) / 1000) + r.amount;
                r.start = bn;
                r.amount = new_amount;
                banks[msg.sender].deposit_records[k] = r;
            }

            if(banks[msg.sender].loan_records[k].isUsed) {
                Record memory r = banks[msg.sender].loan_records[k];
                uint new_amount = (((bn-r.start) * banks[msg.sender].loan_rate * r.amount) / 1000) + r.amount;
                r.start = bn;
                r.amount = new_amount;
                banks[msg.sender].loan_records[k] = r;
            }
        }

        banks[msg.sender].deposit_rate = deposit_rate;
        banks[msg.sender].loan_rate = loan_rate;

        return (banks[msg.sender].deposit_rate, banks[msg.sender].loan_rate);
    }

    /// @notice bank update the rate
    /// @return The total balance of the bank
    function update_max_rate(uint new_max_deposit_rate, uint new_max_loan_rate) public returns (uint, uint) {
        require(msg.sender == owner, "Permission denied!");
        max_deposit_rate = new_max_deposit_rate;
        max_loan_rate = new_max_loan_rate;
        return (max_deposit_rate, max_loan_rate);
    }

    /// @notice query the balance
    /// @return The deposit and loan balance of the user
    function query_balance(address bank) public returns (uint, uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        uint deposit_amount = 0;
        uint loan_amount = 0;
        uint bn = block.number;

        if(banks[bank].deposit_records[msg.sender].isUsed) {
            Record memory r = banks[bank].deposit_records[msg.sender];
            // the new amount
            deposit_amount = (((bn-r.start) * banks[bank].deposit_rate * r.amount) / 1000) + r.amount;
            r.start = bn;
            r.amount = deposit_amount;
            banks[bank].deposit_records[msg.sender] = r;
        }

        if(banks[bank].loan_records[msg.sender].isUsed) {
            Record memory r = banks[bank].loan_records[msg.sender];
            // the new amount
            loan_amount = (((bn-r.start) * banks[bank].loan_rate * r.amount) / 1000) + r.amount;
            r.start = bn;
            r.amount = loan_amount;
            banks[bank].loan_records[msg.sender] = r;
        }

        return (deposit_amount, loan_amount);
    }

    /// @notice query the rate
    /// @return The deposit and loan rate of the bank
    function query_rate(address bank) public view returns (string memory, uint, uint) {
        require(banks[bank].isUsed, "Bank is not registered");
        return (banks[bank].name, banks[bank].deposit_rate, banks[bank].loan_rate);
    }
    
    /// @notice query the banks
    /// @return the bank addresses
    function query_banks() public view returns (address[] memory) {
        return (bank_accounts);
    }
}
