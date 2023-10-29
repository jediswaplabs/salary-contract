use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait };
use tests::utils::{ deployer_addr, USDC, MASTER};


#[starknet::interface]
trait ISalary<T> {
    fn owner(self: @T) -> ContractAddress;
    fn token(self: @T) -> ContractAddress;
    fn master(self: @T) -> ContractAddress;
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