// scripts/verify.ts
import { run, ethers } from "hardhat";
import { lpTokenArgs, depositArgs, routerArgs, keeperArgs, escrowArgs } from "../utils/verify-args";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

async function main(contractArgs: any) {
    // Get implementation address from proxy if not provided
    if (!contractArgs.implementation.address && contractArgs.proxy.address) {
        console.log("Getting implementation address from proxy...");
        const implementationAddress = await getImplementationAddress(ethers.provider, contractArgs.proxy.address);
        contractArgs.implementation.address = implementationAddress;
        console.log(`Implementation address: ${implementationAddress}`);
    }

    // Verify implementation
    console.log("Verifying implementation contract...");
    try {
        await run("verify:verify", {
            address: contractArgs.implementation.address,
            constructorArguments: contractArgs.implementation.args
        });
    } catch (error: any) {
        if (error.message.toLowerCase().includes("already verified")) {
            console.log("Implementation contract already verified!");
        } else {
            console.error("Error verifying implementation:", error);
        }
    }

    // Verify proxy
    console.log("Verifying proxy contract...");
    try {
        await run("verify:verify", {
            address: contractArgs.proxy.address,
            constructorArguments: contractArgs.proxy.args
        });
    } catch (error: any) {
        if (error.message.toLowerCase().includes("already verified")) {
            console.log("Proxy contract already verified!");
        } else {
            console.error("Error verifying proxy:", error);
        }
    }
}

const contractArgs = lpTokenArgs; // depositArgs or lpTokenArgs, routerArgs, keeperArgs, escrowArgs
main(contractArgs)
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });