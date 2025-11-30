// Minimal ERC20 for ZpaceShip integration (very small, illustrative)
// - initializer(name, symbol)
// - mint(recipient, amount)
// - burn(account, amount)
// - transfer(recipient, amount) -> bool
// - balance_of(account) -> u256

#[starknet::contract]
mod MinimalERC20 {
    use starknet::ContractAddress;
    use starknet::storage::*;
    use core::starknet::uint256::Uint256;
    use core::starknet::uint256;

    #[storage]
    pub struct Storage {
        total_supply: Uint256,
        balances: Map<ContractAddress, Uint256>,
        name: felt252,
        symbol: felt252,
        decimals: u8,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Transfer: Transfer,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Transfer {
        pub from: ContractAddress,
        pub to: ContractAddress,
        pub value: Uint256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.total_supply.write(Uint256::from(0_u128));
        self.decimals.write(18_u8);
    }

    // minimal initializer to set metadata
    pub fn initializer(ref self: ContractState, name: felt252, symbol: felt252) {
        self.name.write(name);
        self.symbol.write(symbol);
    }

    pub fn total_supply(ref self: ContractState) -> Uint256 {
        self.total_supply.read()
    }

    pub fn balance_of(ref self: ContractState, owner: ContractAddress) -> Uint256 {
        self.balances.entry(owner).read()
    }

    pub fn mint(ref self: ContractState, recipient: ContractAddress, amount: Uint256) {
        let prev = self.balances.entry(recipient).read();
        let updated = uint256::add(prev, amount);
        self.balances.entry(recipient).write(updated);
        let ts = self.total_supply.read();
        let new_ts = uint256::add(ts, amount);
        self.total_supply.write(new_ts);
        self.emit(Event::Transfer(Transfer { from: 0.into(), to: recipient, value: amount }));
    }

    pub fn burn(ref self: ContractState, account: ContractAddress, amount: Uint256) {
        let prev = self.balances.entry(account).read();
        // naive check: assume prev >= amount
        let new_bal = uint256::sub(prev, amount);
        self.balances.entry(account).write(new_bal);
        let ts = self.total_supply.read();
        let new_ts = uint256::sub(ts, amount);
        self.total_supply.write(new_ts);
        self.emit(Event::Transfer(Transfer { from: account, to: 0.into(), value: amount }));
    }

    pub fn transfer(ref self: ContractState, recipient: ContractAddress, amount: Uint256) -> bool {
        let caller = starknet::get_caller_address();
        let prev = self.balances.entry(caller).read();
        let new_sender = uint256::sub(prev, amount);
        self.balances.entry(caller).write(new_sender);
        let prev_to = self.balances.entry(recipient).read();
        let new_to = uint256::add(prev_to, amount);
        self.balances.entry(recipient).write(new_to);
        self.emit(Event::Transfer(Transfer { from: caller, to: recipient, value: amount }));
        true
    }
}
