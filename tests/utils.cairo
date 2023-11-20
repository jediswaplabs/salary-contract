use starknet:: { ContractAddress, contract_address_try_from_felt252, contract_address_const };

const TOKEN_MULTIPLIER: u256 = 1000000000000000000;


fn deployer_addr() -> ContractAddress {
    contract_address_try_from_felt252('deployer').unwrap()
}


fn zero_addr() -> ContractAddress {
    contract_address_const::<0>()
}

fn user1() -> ContractAddress {
    contract_address_try_from_felt252('user1').unwrap()
}

fn user2() -> ContractAddress {
    contract_address_try_from_felt252('user2').unwrap()
}

fn user3() -> ContractAddress {
    contract_address_try_from_felt252('user3').unwrap()
}

fn user4() -> ContractAddress {
    contract_address_try_from_felt252('user4').unwrap()
}

fn USDC() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}

fn MASTER() -> ContractAddress {
    contract_address_try_from_felt252('master').unwrap()
}

fn MOCK_GUILD1() -> ContractAddress {
    contract_address_try_from_felt252('guild1').unwrap()
}
fn MOCK_GUILD2() -> ContractAddress {
    contract_address_try_from_felt252('guild2').unwrap()
}
fn MOCK_GUILD3() -> ContractAddress {
    contract_address_try_from_felt252('guild3').unwrap()
}
fn MOCK_GUILD4() -> ContractAddress {
    contract_address_try_from_felt252('guild4').unwrap()
}
fn MOCK_GUILD5() -> ContractAddress {
    contract_address_try_from_felt252('guild5').unwrap()
}

fn URI() -> Span<felt252> {
    let mut uri = ArrayTrait::new();

    uri.append('api.jediswap/');
    uri.append('guildSBT/');
    uri.append('dev/');

    uri.span()
}