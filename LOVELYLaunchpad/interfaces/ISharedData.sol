// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.15;

interface ISharedData {
    struct Token {
        //address of salas token
        address token;
    }

    struct PurchaseToken {
        //address of purchase token
        address token;
    }

    struct DexPool {
        address tokenOne;

        address tokenTwo;
    }

    struct PublicSaleParams {

        //min sale cap
        uint256 softCap;

        //max sale cap
        uint256 hardCap;

        //min amount of deposit
        uint256 minContributionLimit;

        //max amount for deposit
        uint256 maxContributionLimit;

        //start deposit block
        uint256 startDepositTime;

        //end deposit block
        uint256 endDepositTime;

        //amount of currency per payment token unit
        uint256 presaleRate;

        //variable that sets deposit type
        bool useNativeToken;

        //address of the token for which we are participating in the ilo
        // PurchaseToken _purchaseToken;

        //sale owner address
        address saleOwner;

        //sales token information
        Token _salesToken;

        //extra quantity percentage
        uint256 extraQuantity;

        // DexPool pool;
    }

}