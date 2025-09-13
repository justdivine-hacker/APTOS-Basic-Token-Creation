module token_creator::basic_token {
    use std::string;
    use std::signer;
    use std::error;
    use aptos_framework::coin::{Self, MintCapability, FreezeCapability, BurnCapability};

    /// Error codes
    const E_NOT_OWNER: u64 = 1;
    const E_TOKEN_ALREADY_EXISTS: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;

    /// Token configuration structure
    struct TokenConfig<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
        owner: address,
    }

    /// Initialize a new token
    public entry fun create_token<CoinType>(
        account: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        initial_supply: u64,
        monitor_supply: bool,
    ) {
        let account_addr = signer::address_of(account);
        
        // Ensure token doesn't already exist
        assert!(!exists<TokenConfig<CoinType>>(account_addr), error::already_exists(E_TOKEN_ALREADY_EXISTS));

        // Convert byte vectors to strings
        let token_name = string::utf8(name);
        let token_symbol = string::utf8(symbol);

        // Initialize the coin
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            account,
            token_name,
            token_symbol,
            decimals,
            monitor_supply,
        );

        // Mint initial supply BEFORE storing capabilities
        let coins = if (initial_supply > 0) {
            coin::mint<CoinType>(initial_supply, &mint_cap)
        } else {
            coin::zero<CoinType>()
        };

        // Store capabilities in TokenConfig
        move_to(account, TokenConfig<CoinType> {
            mint_cap,
            freeze_cap,
            burn_cap,
            owner: account_addr,
        });

        // Deposit initial supply after storing capabilities
        if (initial_supply > 0) {
            coin::deposit<CoinType>(account_addr, coins);
        } else {
            coin::destroy_zero(coins);
        };
    }

    /// Mint additional tokens (only owner can call this)
    public entry fun mint_tokens<CoinType>(
        account: &signer,
        to: address,
        amount: u64,
    ) acquires TokenConfig {
        let account_addr = signer::address_of(account);
        let token_config = borrow_global<TokenConfig<CoinType>>(account_addr);
        
        // Check if caller is the owner
        assert!(token_config.owner == account_addr, error::permission_denied(E_NOT_OWNER));

        // Mint tokens
        let coins = coin::mint<CoinType>(amount, &token_config.mint_cap);
        coin::deposit<CoinType>(to, coins);
    }

    /// Burn tokens from caller's account
    public entry fun burn_tokens<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires TokenConfig {
        let account_addr = signer::address_of(account);
        
        // Check if token config exists
        assert!(exists<TokenConfig<CoinType>>(account_addr), error::not_found(E_TOKEN_ALREADY_EXISTS));
        
        let token_config = borrow_global<TokenConfig<CoinType>>(account_addr);
        let coins = coin::withdraw<CoinType>(account, amount);
        coin::burn<CoinType>(coins, &token_config.burn_cap);
    }

    /// Transfer tokens between accounts
    public entry fun transfer<CoinType>(
        from: &signer,
        to: address,
        amount: u64,
    ) {
        let coins = coin::withdraw<CoinType>(from, amount);
        coin::deposit<CoinType>(to, coins);
    }

    #[view]
    public fun balance<CoinType>(account: address): u64 {
        coin::balance<CoinType>(account)
    }

    #[view]
    public fun is_account_registered<CoinType>(account: address): bool {
        coin::is_account_registered<CoinType>(account)
    }

    public entry fun register<CoinType>(account: &signer) {
        coin::register<CoinType>(account);
    }

    #[view]
    public fun get_token_owner<CoinType>(token_creator: address): address acquires TokenConfig {
        borrow_global<TokenConfig<CoinType>>(token_creator).owner
    }

    /// Freeze an account (only owner can call this)
    public entry fun freeze_account<CoinType>(
        account: &signer,
        account_to_freeze: address,
    ) acquires TokenConfig {
        let account_addr = signer::address_of(account);
        let token_config = borrow_global<TokenConfig<CoinType>>(account_addr);
        
        assert!(token_config.owner == account_addr, error::permission_denied(E_NOT_OWNER));
        coin::freeze_coin_store<CoinType>(account_to_freeze, &token_config.freeze_cap);
    }

    /// Unfreeze an account (only owner can call this)
    public entry fun unfreeze_account<CoinType>(
        account: &signer,
        account_to_unfreeze: address,
    ) acquires TokenConfig {
        let account_addr = signer::address_of(account);
        let token_config = borrow_global<TokenConfig<CoinType>>(account_addr);
        
        assert!(token_config.owner == account_addr, error::permission_denied(E_NOT_OWNER));
        coin::unfreeze_coin_store<CoinType>(account_to_unfreeze, &token_config.freeze_cap);
    }

    #[test_only]
    use aptos_framework::account::create_account_for_test;

    #[test_only]
    struct TestCoin {}

    #[test]
    public fun test_token_creation() acquires TokenConfig {
        let creator = create_account_for_test(@0x123);
        
        create_token<TestCoin>(
            &creator,
            b"Test Token",
            b"TEST",
            8,
            1000000,
            true
        );

        assert!(balance<TestCoin>(@0x123) == 1000000, 1);
        assert!(get_token_owner<TestCoin>(@0x123) == @0x123, 2);
    }

    #[test]
    public fun test_mint_and_transfer() acquires TokenConfig {
        let creator = create_account_for_test(@0x123);
        let user = create_account_for_test(@0x456);
        
        create_token<TestCoin>(
            &creator,
            b"Test Token",
            b"TEST",
            8,
            0,
            true
        );

        register<TestCoin>(&user);
        mint_tokens<TestCoin>(&creator, @0x456, 500);
        
        assert!(balance<TestCoin>(@0x456) == 500, 3);
    }
}