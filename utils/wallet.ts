import { ethers } from "hardhat"
import * as helpers from "@nomicfoundation/hardhat-network-helpers"

export async function getSigners(networkName: string, forkedChain: string[]) {
    if (forkedChain.includes(networkName)) {
        await helpers.mine()
        const provider = ethers.provider
        return {
            owner1: new ethers.Wallet(process.env.PRIVATE_KEY_ADMIN!, provider),
            owner2: new ethers.Wallet(process.env.PRIVATE_KEY_TWO!, provider),
            owner3: new ethers.Wallet(process.env.PRIVATE_KEY_SEQ!, provider)
        }
    }
    const [owner1, owner2, owner3] = await ethers.getSigners()
    return { owner1, owner2, owner3 }
}
