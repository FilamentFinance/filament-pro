import { ethers, network } from "hardhat"
import * as netMap from "../constants/networkMapping.json"
import { forkedChain } from "../helper-hardhat-config"
import * as helpers from "@nomicfoundation/hardhat-network-helpers"

import { tradeFacetSelectors, vaultFacetSelectors, viewFacetSelectors } from "../utils/facetSelectors"

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
    const TradeFacet = await ethers.getContractFactory("TradeFacet", deployer)
    const tradeFacet = await TradeFacet.deploy()
    await tradeFacet.waitForDeployment()
    console.log("TradeFacet deployed to:", tradeFacet.target)

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
        {
            facetAddress: tradeFacet.target,
            action: FacetCutAction.Replace, // 0 means Add, 1 for Replace, 2 for Remove
            functionSelectors: tradeFacetSelectors
        },
        // {
        //     facetAddress: vaultFacet.target,
        //     action: FacetCutAction.Replace, // 0 means Add, 1 for Replace, 2 for Remove
        //     functionSelectors: vaultFacetSelectors
        // },
        // {
        //     facetAddress: viewFacet.target,
        //     action: FacetCutAction.Replace, // 0 means Add, 1 for Replace, 2 for Remove
        //     functionSelectors: viewFacetSelectors
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
