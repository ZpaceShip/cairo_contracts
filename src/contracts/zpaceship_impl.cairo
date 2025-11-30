// ZpaceShip launchpad - sale management with privacy commitments
// Minimal, single-contract launchpad with commitment-based privacy and token integration.

// NOTE: Manually check the logic to even simplify more, but this task must be done by a human. 

#[starknet::contract]
pub mod ZpaceShip {
    use starknet::ContractAddress;
    use starknet::storage::*;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use core::starknet::uint256::Uint256;
    use core::starknet::uint256;
    use core::hash;
    use interfaces::Ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    pub struct Storage {
        // Simple incrementing sale id
        sale_count: u64,

        // Per-sale fields stored as separate maps (keys: sale_id)
        sale_token: Map<u64, ContractAddress>,
        sale_name: Map<u64, felt252>,
        sale_symbol: Map<u64, felt252>,
        sale_total_supply: Map<u64, Uint256>,
        sale_duration: Map<u64, u64>,
        sale_start: Map<u64, u64>,
        sale_sold: Map<u64, Uint256>,
        sale_finalized: Map<u64, bool>,
        sale_owner: Map<u64, ContractAddress>,

        // Map token address -> sale_id (set when token_address is registered)
        token_to_sale: Map<ContractAddress, u64>,

        // Commitments mapping: maps hashed key -> donated amount (u256)
        // Key is computed off-chain as pedersen(sale_id, commitment_felt) to avoid nested maps.
        commitments: Map<felt252, Uint256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SaleCreated: SaleCreated,
        TokensBought: TokensBought,
        SaleFinalized: SaleFinalized,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SaleCreated {
        pub sale_id: u64,
        pub owner: ContractAddress,
        pub total_supply: Uint256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokensBought {
        pub sale_id: u64,
        pub commitment: felt252,
        pub amount: Uint256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SaleFinalized {
        pub sale_id: u64,
        pub tokens_sold: Uint256,
        pub tokens_burned: Uint256,
        pub finalizer: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.sale_count.write(0_u64);
    }

    // Helper: compute commitment storage key = pedersen(sale_id, commitment)
    fn make_commit_key(sale_id: u64, commitment: felt252) -> felt252 {
        let sale_felt = sale_id as felt252;
        let key = hash::pedersen(sale_felt, commitment);
        key
    }

    // 1) Create token sale record. NOTE: this function records the sale metadata and returns a sale id.
    // The actual ERC20 token deployment should be done off-chain (OpenZeppelin ERC20). After token
    // deployment, call `register_token_address(sale_id, token_address)` from the sale owner.

    pub fn create_token(ref self: ContractState, name: felt252, symbol: felt252, total_supply: Uint256, sale_duration: u64) -> u64 {
        let caller = get_caller_address();
        let mut id = self.sale_count.read();
        id = id + 1_u64;
        self.sale_count.write(id);

        self.sale_name.entry(id).write(name);
        self.sale_symbol.entry(id).write(symbol);
        self.sale_total_supply.entry(id).write(total_supply);
        self.sale_duration.entry(id).write(sale_duration);
        // start time recorded now
        let now = get_block_timestamp();
        self.sale_start.entry(id).write(now);
        self.sale_sold.entry(id).write(Uint256::from(0_u128));
        self.sale_finalized.entry(id).write(false);
        self.sale_owner.entry(id).write(caller);

        self.emit(Event::SaleCreated(SaleCreated { sale_id: id, owner: caller, total_supply }));

        id
    }

    // Helper: owner registers the token contract address after deploying the ERC20 off-chain.
    pub fn register_token_address(ref self: ContractState, sale_id: u64, token_address: ContractAddress) {
        let caller = get_caller_address();
        let owner = self.sale_owner.entry(sale_id).read();
        assert!(caller == owner, "Only owner can register token address");
        self.sale_token.entry(sale_id).write(token_address);
        self.token_to_sale.entry(token_address).write(sale_id);
    }

    // 2) buy_tokens with privacy: user computes off-chain a commitment = pedersen(user_address, salt)
    // and supplies that commitment here along with `amount`. The contract records the amount under
    // the commitment. Payment flow (sending ETH / stablecoin) is out-of-scope here and should be
    // handled by a separate token transfer into escrow before/after calling this function.
    pub fn buy_tokens(ref self: ContractState, token_address: ContractAddress, amount: Uint256, commitment: felt252) {
        let sale_id = self.token_to_sale.entry(token_address).read();

        // ensure sale exists and not finalized
        let finalized = self.sale_finalized.entry(sale_id).read();
        assert!(!finalized, "Sale finalized");

        // increment sold
        let prev_sold = self.sale_sold.entry(sale_id).read();
        let new_sold = uint256::add(prev_sold, amount);
        self.sale_sold.entry(sale_id).write(new_sold);

        // store commitment -> amount (additive if same commitment used multiple times)
        let key = make_commit_key(sale_id, commitment);
        let prev = self.commitments.entry(key).read();
        let updated = uint256::add(prev, amount);
        self.commitments.entry(key).write(updated);

        self.emit(Event::TokensBought(TokensBought { sale_id, commitment, amount }));
    }

    // 3) finalize_sale: can be called by anyone but will only finalize when duration passed or sold-out
    pub fn finalize_sale(ref self: ContractState, token_address: ContractAddress) -> (Uint256, Uint256) {
        let sale_id = self.token_to_sale.entry(token_address).read();
        let finalized = self.sale_finalized.entry(sale_id).read();
        assert!(!finalized, "Already finalized");

        let start = self.sale_start.entry(sale_id).read();
        let duration = self.sale_duration.entry(sale_id).read();
        let now = get_block_timestamp();

        let total_supply = self.sale_total_supply.entry(sale_id).read();
        let sold = self.sale_sold.entry(sale_id).read();

        // condition: either time passed or sold == total_supply
        let sold_out = uint256::eq(sold, total_supply);
        assert!(now >= start + duration || sold_out, "Sale still active");

        // compute burned = total_supply - sold (if sold < total_supply)
        let tokens_burned = if uint256::lt(sold, total_supply) {
            uint256::sub(total_supply, sold)
        } else {
            Uint256::from(0_u128)
        };

        // mark finalized
        self.sale_finalized.entry(sale_id).write(true);

        let caller = get_caller_address();

        // If there are tokens to burn, call token.burn(contract_address, amount).
        if uint256::lt(Uint256::from(0_u128), tokens_burned) {
            let our_addr = get_contract_address();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            erc20.burn(our_addr, tokens_burned);
        }

        // Optional: transfer a fee percentage of proceeds to caller (owner of finalize)
        // For simplicity we do not hold proceeds here; integrate fee logic with actual escrow/token transfer off-chain or via additional token conventions.

        self.emit(Event::SaleFinalized(SaleFinalized { sale_id, tokens_sold: sold, tokens_burned, finalizer: caller }));

        (sold, tokens_burned)
    }

    // 4) get_user_balance (private): user presents preimage (salt) to prove ownership of a commitment
    // NOTE: we include `salt` param so the contract can recompute commitment = pedersen(user, salt)
    // and return the amount stored.
    fn get_user_balance(ref self: ContractState, token_address: ContractAddress, user: ContractAddress, salt: felt252) -> Uint256 {
        let sale_id = self.token_to_sale.entry(token_address).read();
        let commitment = hash::pedersen(user, salt);
        let key = make_commit_key(sale_id, commitment);
        let amount = self.commitments.entry(key).read();
        amount
    }

    // Helper public wrapper to allow a user to reveal their preimage and claim balance off-chain or via another flow.
    pub fn reveal_and_get_balance(ref self: ContractState, token_address: ContractAddress, salt: felt252) -> Uint256 {
        let caller = get_caller_address();
        self.get_user_balance(token_address, caller, salt)
    }

    // Claim committed tokens: user reveals salt, contract transfers tokens from itself to caller.
    pub fn claim(ref self: ContractState, token_address: ContractAddress, salt: felt252) {
        let caller = get_caller_address();

        // read committed amount
        let amount = self.get_user_balance(token_address, caller, salt);
        // require non-zero
        assert!(uint256::lt(Uint256::from(0_u128), amount), "No committed amount");

        // zero out commitment to prevent re-claim
        let sale_id = self.token_to_sale.entry(token_address).read();
        let commitment = hash::pedersen(caller, salt);
        let key = make_commit_key(sale_id, commitment);
        self.commitments.entry(key).write(Uint256::from(0_u128));

        // transfer tokens from this contract (assumes tokens were minted/transferred to this contract)
        let erc20 = IERC20Dispatcher { contract_address: token_address };
        let success = erc20.transfer(caller, amount);
        assert!(success, "Token transfer failed");
    }

}
