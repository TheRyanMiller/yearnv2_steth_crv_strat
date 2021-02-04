from itertools import count
from brownie import Wei, reverts
import eth_abi
from brownie.convert import to_bytes
from useful_methods import genericStateOfStrat,genericStateOfVault
import random
import brownie

# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

def test_opsss(voter, steth_gauge, currency,strategy,zapper,strategyProxy,Contract, ldo, rewards,chain,vault, ychad, whale,gov,strategist, interface):
    rate_limit = 1_000_000_000 *1e18
    debt_ratio = 10_000
    vault.addStrategy(strategy, debt_ratio, rate_limit, 1000, {"from": gov})
    strategyProxy.setGovernance(gov,{"from":strategist})
    strategyProxy.approveStrategy(strategy,{"from":gov}) # Whitelist our strategy
    voter.setStrategy(strategyProxy.address ,{"from":ychad})
    
    strategy.setProxy(strategyProxy, {"from": gov})

    #mooni = Contract.from_explorer('0x1f629794B34FFb3B29FF206Be5478A52678b47ae')

    currency.approve(vault, 2 ** 256 - 1, {"from": whale} )
    #ldo.approve(mooni, 2 ** 256 - 1, {"from": whale} )
    
    #mooni.swap(ldo, '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', 1000*1e18, 1, whale, {"from": whale})

    whalebefore = currency.balanceOf(whale)
    whale_deposit  = 100 *1e18
    vault.deposit(whale_deposit, {"from": whale})
    
    strategy.harvest({'from': strategist})

    genericStateOfStrat(strategy, currency, vault)
    genericStateOfVault(vault, currency)

    chain.sleep(2592000) # Thirty days
    chain.mine(1)

    
    
    strategy.harvest({'from': strategist})
    steth = interface.ERC20('0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84')

    print("====================LDO TOKENS")
    print(strategyProxy.balanceOf(steth_gauge.address) / 1e18)
    print(strategy.rewardsBalance("0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"))
    print(ldo.balanceOf(strategy.address))
    print(ldo.balanceOf(voter.address))
    print(ldo.balanceOf(strategyProxy.address))
    print("====================")

    stethbal = steth.balanceOf(strategy)
    ethbal = strategy.balance()
    assert stethbal <= 1
    assert ethbal <= 1
    assert ldo.balanceOf(strategy) == 0

    print("steth = ", stethbal/1e18)
    print("eth = ", ethbal/1e18)

    genericStateOfStrat(strategy, currency, vault)
    genericStateOfVault(vault, currency)

    #print(mooni.balanceOf(strategist))

    print("\nEstimated APR: ", "{:.2%}".format(((vault.totalAssets()-100*1e18)*12)/(100*1e18)))

    vault.withdraw({"from": strategist})
    vault.withdraw({"from": whale})
    vault.withdraw({"from": rewards})
    
    print("\nWithdraw")
    genericStateOfStrat(strategy, currency, vault)
    genericStateOfVault(vault, currency)
    print("Whale profit: ", (currency.balanceOf(whale) - whalebefore)/1e18)

