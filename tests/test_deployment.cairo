use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait };
use tests::utils::{ deployer_addr, USDC, MASTER, MOCK_GUILD1, MOCK_GUILD2, MOCK_GUILD3, MOCK_GUILD4, MOCK_GUILD5};


#[starknet::interface]
trait ISalary<T> {
    fn owner(self: @T) -> ContractAddress;
    fn token(self: @T) -> ContractAddress;
    fn master(self: @T) -> ContractAddress;
}

#[starknet::interface]
trait ISalary2<T> {
    fn owner(self: @T) -> ContractAddress;
    fn token(self: @T) -> ContractAddress;
    fn master(self: @T) -> ContractAddress;
    fn guild_contract(self: @T, guild: felt252) -> ContractAddress;
}


#[test]
fn test_deployment_salary() { 
    let mut salary_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref salary_constructor_calldata);
    Serde::serialize(@USDC(), ref salary_constructor_calldata);
    Serde::serialize(@MASTER(), ref salary_constructor_calldata);
    let salary_class = declare('SalaryDistributor');
    let salary_address = salary_class.deploy(@salary_constructor_calldata).unwrap();
    
    // Create a Dispatcher object that will allow interacting with the deployed contract
    let salary_dispatcher = ISalaryDispatcher { contract_address: salary_address };

    let owner = salary_dispatcher.owner();
    assert(owner == deployer_addr(), 'Invalid Owner');

    let token = salary_dispatcher.token();
    assert(token == USDC(), 'Invalid token');

    let master = salary_dispatcher.master();
    assert(master == MASTER(), 'Invalid master');
}

#[test]
fn test_deployment_salary2() { 
    let mut guilds: Array<ContractAddress> = ArrayTrait::new();
    guilds.append(MOCK_GUILD1());
    guilds.append(MOCK_GUILD2());
    guilds.append(MOCK_GUILD3());
    guilds.append(MOCK_GUILD4());
    guilds.append(MOCK_GUILD5());

    let mut salary_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref salary_constructor_calldata);
    Serde::serialize(@USDC(), ref salary_constructor_calldata);
    Serde::serialize(@MASTER(), ref salary_constructor_calldata);
    Serde::serialize(@guilds, ref salary_constructor_calldata);
    let salary_class = declare('SalaryDistributor2');
    let salary_address = salary_class.deploy(@salary_constructor_calldata).unwrap();
    // Create a Dispatcher object that will allow interacting with the deployed contract
    let salary_dispatcher = ISalary2Dispatcher { contract_address: salary_address };

    let owner = salary_dispatcher.owner();
    assert(owner == deployer_addr(), 'Invalid Owner');

    let token = salary_dispatcher.token();
    assert(token == USDC(), 'Invalid token');

    let master = salary_dispatcher.master();
    assert(master == MASTER(), 'Invalid master');

    let dev_guild = salary_dispatcher.guild_contract('dev');
    assert(dev_guild == MOCK_GUILD1(), 'Invalid dev guild');
    
    let design_guild = salary_dispatcher.guild_contract('design');
    assert(design_guild == MOCK_GUILD2(), 'Invalid design guild');

    let problem_solving_guild = salary_dispatcher.guild_contract('problem_solving');
    assert(problem_solving_guild == MOCK_GUILD3(), 'Invalid problem_solving guild');

    let marcom_guild = salary_dispatcher.guild_contract('marcom');
    assert(marcom_guild == MOCK_GUILD4(), 'Invalid marcom guild');

    let research_guild = salary_dispatcher.guild_contract('research');
    assert(research_guild == MOCK_GUILD5(), 'Invalid research guild');

}