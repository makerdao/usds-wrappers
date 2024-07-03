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
    function pocket() external view returns (address);
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
    function buf() external view returns (uint256);
    function sellGem(address, uint256) external returns (uint256);
    function buyGem(address, uint256) external returns (uint256);
    function ilk() external view returns (bytes32);
    function vow() external view returns (address);
    function live() external view returns (uint256);
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
    DaiJoinLike internal immutable legacyDaiJoin;
    NstJoinLike public   immutable nstJoin;
    GemLike     internal immutable legacyDai;
    GemLike     public   immutable nst;
    VatLike     public   immutable vat;
    uint256     public   immutable to18ConversionFactor;

    uint256 constant WAD = 10 ** 18;
    uint256 public constant HALTED = type(uint256).max; // For backwards compatibility with the Lite PSM

    constructor(address psm_, address nstJoin_) {
        psm           = PsmLike(psm_);
        gem           = GemLike(psm.gem());
        legacyDaiJoin = DaiJoinLike(psm.daiJoin());
        nstJoin       = NstJoinLike(nstJoin_);
        legacyDai     = GemLike(legacyDaiJoin.dai());
        nst           = GemLike(nstJoin.nst());
        vat           = VatLike(psm.vat());

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        legacyDai.approve(address(psm), type(uint256).max);
        gem.approve(address(psm), type(uint256).max);

        legacyDai.approve(address(legacyDaiJoin), type(uint256).max);
        nst.approve(address(nstJoin), type(uint256).max);

        vat.hope(address(legacyDaiJoin));
        vat.hope(address(nstJoin));
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 nstOutWad) {
        gem.transferFrom(msg.sender, address(this), gemAmt);
        nstOutWad = psm.sellGem(address(this), gemAmt);
        legacyDaiJoin.join(address(this), nstOutWad);
        nstJoin.exit(usr, nstOutWad);
    }

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 nstInWad) {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        nstInWad = gemAmt18 + gemAmt18 * psm.tout() / WAD;
        nst.transferFrom(msg.sender, address(this), nstInWad);
        nstJoin.join(address(this), nstInWad);
        legacyDaiJoin.exit(address(this), nstInWad);
        psm.buyGem(usr, gemAmt);
    }

    // Partial Backward Compatibility Getters With the Lite Psm

    function ilk() external view returns (bytes32) {
        return psm.ilk();
    }

    function vow() external view returns (address) {
        return psm.vow();
    }

    function dai() external view returns (address) {
        return address(nst); // Supports not changing integrating code that works with the legacy dai based lite psm
    }

    function gemJoin() external view returns (address) {
        return address(this); // Supports not changing integrating code that queries and approves the gemJoin
    }

    function pocket() external view returns (address) {
        return psm.pocket();
    }

    function tin() external view returns (uint256) {
        return psm.tin();
    }

    function tout() external view returns (uint256) {
        return psm.tout();
    }

    function buf() external view returns (uint256) {
        return psm.buf();
    }

    function dec() external view returns (uint256) {
        return gem.decimals();
    }

    function live() external view returns (uint256) {
        return psm.live();
    }
}
