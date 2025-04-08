const usdc = "0x3894085Ef7Ff0f0aeDf52E2A2704928d1Ec074F1"
const protocolTreasury = "0xf38BdB166222A423528c38bD719F7Ae15E90dEbE"
const liquidators = ["0x1cbB9A313AD4A50459283F2C2Ac74A5dA0689007", "0xbCffe4c42E8186B4770d5269015940E074D2eE00"]
const insurance = "0x121B34238CC8A2Bc5DFA22c2C3ac0964b1E3264b"

export const depositArgs = {
    implementation: {
        address: "0xa27a13c3211B7DEB2E806b67C372B24FB6779d97",
        args: []
    },
    proxy: {
        address: "0x7540F45b330D489491f7e873E0993F117bDDB56F",
        args: ["0x3894085Ef7Ff0f0aeDf52E2A2704928d1Ec074F1"], // usdc
    }
};

export const lpTokenArgs = {
    implementation: {
        address: "0x0938299bf55Bc09A2c5930F3aCAdcB024804178f",
        args: []
    },
    proxy: {
        address: "0xCda5A7417b42A6De5ef927081e9A55fc77d90dff",
        args: ["0x3894085Ef7Ff0f0aeDf52E2A2704928d1Ec074F1", "Filament LP Token", "FLP"], // usdc, name, symbol
    }
};

export const routerArgs = {
    implementation: {
        address: "",
        args: []
    },
    proxy: {
        address: "0x5C4ddf61934BB27827a2337d351722b9C732f5D2",
        args: []
    }
};

export const keeperArgs = {
    implementation: {
        address: "",
        args: []
    },
    proxy: {
        address: "0x47606E2Bd67C1A0162B2C2bEf2cB79a262e17c88",
        args: [usdc, protocolTreasury, insurance]
    }
};

export const escrowArgs = {
    implementation: {
        address: "",
        args: []
    },
    proxy: {
        address: "0xA2124a59722aef08CF856c836A579a1F9fB9c94a",
        args: [usdc]
    }
};

export const diamondArgs = {
    proxy: {
        address: "",
        args: []
    }
};




