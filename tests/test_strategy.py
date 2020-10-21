from brownie import Wei

def test_strategy(accounts, interface, chain, YearnCompDaiStrategy):
    user = accounts[0]
    whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    solo = interface.ISoloMargin('0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e')
    comptroller = interface.ComptrollerI('0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b')
    dai = interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')
    cdai = interface.CErc20I('0x5d3a536e4d6dbd6114cc1ead35777bab948e3643')
    comp = interface.ERC20('0xc00e94cb662c3520282e6f5717214004a7f26888')
    controller = interface.IController('0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080')
    strategy = YearnCompDaiStrategy.deploy(controller, {'from': user})

    amount = dai.balanceOf(whale) - dai.balanceOf(whale) % Wei('1000000 ether')
    # force-deposit, todo: use a proper vault flow
    dai.transfer(strategy, amount, {'from': whale})
    print('dai deposit:', dai.balanceOf(strategy).to('ether'))
    strategy.deposit()
    
    print('borrowable:', comptroller.getAccountLiquidity(strategy))
    print('dai balance:', dai.balanceOf(strategy).to('ether'))
    print('cdai balance:', cdai.balanceOf(strategy).to('ether'))
    deposits, borrows = strategy.getCurrentPosition()
    print('deposits:', Wei(deposits).to('ether'))
    print('borrows:', Wei(borrows).to('ether'))
    before = strategy.balanceOf()
    print('balanceOf before:', before.to('ether'))

    print('sleep and call harvest')
    blocks_per_year = 2_300_000
    sample = 100
    chain.mine(sample)
    strategy.harvest()
    after = strategy.balanceOf()
    assert after > before
    print('balanceOf after:', after.to('ether'))
    print('balance increase:', (after - before).to('ether'))
    print(f'implied apr: {(after / before - 1) * (blocks_per_year / sample):.8%}')

    strategy.withdraw(amount)
