import { ethers, network } from "hardhat"
import * as netMap from "../constants/networkMapping.json"
import { forkedChain } from "../helper-hardhat-config"
import * as helpers from "@nomicfoundation/hardhat-network-helpers"
import { FacetCutAction } from "../utils/constants"

async function main() {
    let tx, txr, deployer
    const networkName = network.name as keyof typeof netMap
    const diamondAddress = (netMap[networkName] as any).Diamond

    if (forkedChain.includes(networkName)) {
        await helpers.mine()
        const provider = ethers.provider
        deployer = new ethers.Wallet(process.env.PRIVATE_KEY_ADMIN!.toString(), provider)
    } else {
        ;[deployer] = await ethers.getSigners()
    }
    console.log(deployer?.address)
    console.log(await ethers.provider.getBalance(deployer?.address))

    const DiamondCutFacet = await ethers.getContractAt("IDiamondCut", diamondAddress, deployer)

    // Deploy new facet
    // const TradeFacet = await ethers.getContractFactory("TradeFacet", deployer)
    // const tradeFacet = await TradeFacet.deploy()
    // await tradeFacet.waitForDeployment()
    // console.log("TradeFacet deployed to:", tradeFacet.target)

    const VaultFacet = await ethers.getContractFactory("VaultFacet", deployer)
    const vaultFacet = await VaultFacet.deploy()
    await vaultFacet.waitForDeployment()
    console.log("VaultFacet deployed to:", vaultFacet.target)

    // const ViewFacet = await ethers.getContractFactory("ViewFacet", deployer)
    // const viewFacet = await ViewFacet.deploy()
    // await viewFacet.waitForDeployment()
    // console.log("ViewFacet deployed to:", viewFacet.target)

    // Prepare the cut transaction
    const cut: any = [
        // {
        //     facetAddress: "0x0000000000000000000000000000000000000000",
        //     action: FacetCutAction.Remove, // 0 means Add ,  1 Replace function , 2 for Remove
        //     functionSelectors: [
        //         // "0xc2c0d396", // decreasePosition((uint256,uint256,uint256,uint256,uint256,address,address,address,uint8,uint8,bool),int256)
        //         // "0x45c1264b", // transferPosition(address,address,bool,uint256,uint256,int256)
        //         // "0x6dece401", // liquidateMatchWithPoolADL(address,address,bool,uint256,int256,uint256)
        //         // "0xd7dd3a4a", // getCurrentCollateral(bytes32,uint256,int256)
        //         // "0x441e9c02", // validateliquidation(bytes32,uint256,int256)
        //         // "0x21a5ee44", // updatePositionForLiquidator(bytes32,bytes32,(uint256,uint256,uint256,uint256,uint256,uint256,uint256,int256,address,bool,(uint256,uint256,uint8),uint256))
        //         // "0xec8bede0", // updateCollateralFromLiquidation((uint256,uint256,uint256,uint256,uint256,uint256,uint256,int256,address,bool,(uint256,uint256,uint8),uint256),bytes32)
        //         // "0xd49ab22c", // getLockedCollateral(address),
        //     ]
        // },
        // {
        //     facetAddress: tradeFacet.target,
        //     action: FacetCutAction.Add,// 0 means Add ,  1 Replace function , 2 for Remove
        //     functionSelectors: [
        //         "0x992a79be", // decreasePosition((uint256,uint256,uint256,uint256,uint256,address,address,address,uint8,uint8,bool,int256,uint256))
        //         "0x22e57524", // transferPosition(address,address,bool,uint256,uint256,int256,uint256)
        //         "0x220fc854", // liquidateMatchWithPoolADL(address,address,bool,uint256,int256,uint256,uint256)
        //         "0xd1679edb", // getCurrentCollateral(bytes32,uint256,int256,uint256)
        //         "0x6154b511", // validateliquidation(bytes32,uint256,int256,uint256)
        //         "0x5f80a9cf" // approveUSDC(uint256)
        //     ]
        // },
        {
            facetAddress: vaultFacet.target,
            action: FacetCutAction.Add, // 0 means Add ,  1 Replace function , 2 for Remove
            functionSelectors: [
                "0xeed18491" // moveCollateralFromRemovedAsset(address, address)
            ]
        }
        // {
        //     facetAddress: viewFacet.target,
        //     action: FacetCutAction.Add, // 0 means Add ,  1Replace function
        //     functionSelectors: [
        //         // "0x035eb918", // getLongCollateral(address)
        //         // "0xf773a8bc", // getShortCollateral(address),
        //         "0x740b9027" // getcumulativeInterestRate(address)
        //     ]
        // }
    ]

    try {
        // Execute the diamond cut
        tx = await DiamondCutFacet.diamondCut(cut, "0x0000000000000000000000000000000000000000", "0x")
        console.log("Diamond cut transaction sent:", tx.hash)
        txr = await tx.wait()
        console.log("Diamond Cut Successfully! ✅✅✅")
    } catch (error: any) {
        console.log("Error", error.message)
        console.error("Diamond cut failed ❌❌❌")
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exitCode = 1
    })
