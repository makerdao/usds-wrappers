// SPDX-FileCopyrightText: © 2024 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

interface PsmLike {
    function gem() external view returns (address);
    function vat() external view returns (address);
    function daiJoin() external view returns (address);
    function tout() external view returns (uint256);
    function sellGem(address, uint256) external returns (uint256);
    function buyGem(address, uint256) external returns (uint256);
}

interface GemLike {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface DaiJoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface NstJoinLike {
    function nst() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
}

// A wrapper around the Lite PSM contract
contract NstPsmWrapper {
    PsmLike     public   immutable psm;
    GemLike     public   immutable gem;
    DaiJoinLike public   immutable daiJoin;
    NstJoinLike public   immutable nstJoin;
    GemLike     public   immutable dai;
    GemLike     public   immutable nst;
    uint256     internal immutable to18ConversionFactor;

    uint256 constant WAD = 10 ** 18;

    constructor(address psm_, address nstJoin_) {
        psm     = PsmLike(psm_);
        gem     = GemLike(psm.gem());
        daiJoin = DaiJoinLike(psm.daiJoin());
        nstJoin = NstJoinLike(nstJoin_);
        dai     = GemLike(daiJoin.dai());
        nst     = GemLike(nstJoin.nst());

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        dai.approve(address(psm), type(uint256).max);
        gem.approve(address(psm), type(uint256).max);

        dai.approve(address(daiJoin), type(uint256).max);
        nst.approve(address(nstJoin), type(uint256).max);

        VatLike vat = VatLike(psm.vat());
        vat.hope(address(daiJoin));
        vat.hope(address(nstJoin));
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 nstOutWad) {
        gem.transferFrom(msg.sender, address(this), gemAmt);
        nstOutWad = psm.sellGem(address(this), gemAmt);
        daiJoin.join(address(this), nstOutWad);
        nstJoin.exit(usr, nstOutWad);
    }

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 nstInWad) {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        nstInWad = gemAmt18 + gemAmt18 * psm.tout() / WAD;
        nst.transferFrom(msg.sender, address(this), nstInWad);
        nstJoin.join(address(this), nstInWad);
        daiJoin.exit(address(this), nstInWad);
        psm.buyGem(usr, gemAmt);
    }
}
