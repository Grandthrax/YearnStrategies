from itertools import count
from brownie import Wei, reverts
import brownie
import random
from useful_methods import stateOf, deposit, earn, harvest, withdraw, initialMigrate

def test_random_operation(accounts, interface, chain, web3, history, YearnCompDaiStrategy):
    user = accounts[0]
    #whale has 29m dai
    whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    ychad = accounts.at(web3.ens.resolve('ychad.eth'), force=True)

    solo = interface.ISoloMargin('0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e')
    comptroller = interface.ComptrollerI('0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b')
    dai = interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')
    cdai = interface.CErc20I('0x5d3a536e4d6dbd6114cc1ead35777bab948e3643')
    comp = interface.ERC20('0xc00e94cb662c3520282e6f5717214004a7f26888')

    controller = interface.IController('0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080')
    vault = interface.IVault(controller.vaults(dai))


    strategy = YearnCompDaiStrategy.deploy(controller, {'from': user})
    assert strategy.want() == vault.token() == dai
    strategy.setWithdrawalFee(0)
   

    initialMigrate(strategy,vault, whale,ychad, dai, controller)
    
    normal_operation(chain, ychad, vault, user, whale, strategy, dai)

    


def normal_operation(chain, ychad, vault, user, whale, strategy, dai):
    print('\n---starting normal operations----')
    for i in count(1):
        waitBlock = random.randint(0,20)
        print(f'\n----wait {waitBlock} blocks----')
        chain.mine(waitBlock)

        action = random.randint(0,3)
        if action ==0:
            harvest(strategy, user)
        elif action == 1:
            withdraw(random.randint(10,100), strategy,whale, dai, vault)
        elif action == 2:
            earn(strategy, vault, user)
        elif action == 3:
            deposit(str(f'{random.randint(1,100000)} ether'), whale, dai, vault)
        
        

    

    


