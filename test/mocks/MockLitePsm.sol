// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

interface VatLike {
    function hope(address) external;
}

interface GemLike {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface DaiJoinLike {
    function dai() external view returns (address);
    function vat() external view returns (address);
}

// Based on https://github.com/makerdao/dss-lite-psm/commit/374bb08b09a3f4798858fd841bab8e79719266c8
// Assumes funds are dealt to it and to the pocket, so DAI minting is not needed
contract MockLitePsm {
    bytes32     public immutable ilk;
    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;
    GemLike     public immutable dai;
    GemLike     public immutable gem;
    uint256     public immutable to18ConversionFactor;
    address     public immutable pocket;

    address public vow;
    uint256 public tin;
    uint256 public tout;
    uint256 public buf;

    uint256 internal constant WAD = 10 ** 18;

    constructor(bytes32 ilk_, address gem_, address daiJoin_, address pocket_) {
        ilk     = ilk_;
        gem     = GemLike(gem_);
        daiJoin = DaiJoinLike(daiJoin_);
        vat     = VatLike(daiJoin.vat());
        dai     = GemLike(daiJoin.dai());
        pocket  = pocket_;

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        dai.approve(daiJoin_, type(uint256).max);
        vat.hope(daiJoin_);
    }

    // Non-authed version for testing, do not copy
    function file(bytes32 what, address data) external {
        if (what == "vow") vow = data;
    }

    // Non-authed version for testing, do not copy
    function file(bytes32 what, uint256 data) external {
        if      (what == "tin")  tin  = data;
        else if (what == "tout") tout = data;
        else if (what == "buf")  buf = data;
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad) {
        daiOutWad = gemAmt * to18ConversionFactor;
        if (tin > 0) daiOutWad -= daiOutWad * tin / WAD;
        gem.transferFrom(msg.sender, pocket, gemAmt);
        dai.transfer(usr, daiOutWad);
    }

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        daiInWad = gemAmt * to18ConversionFactor;
        if (tout > 0) daiInWad += daiInWad * tout / WAD;
        dai.transferFrom(msg.sender, address(this), daiInWad);
        gem.transferFrom(pocket, usr, gemAmt);
    }

    function gemJoin() external view returns (address) {
        return address(this);
    }
}
