// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface INFTMarketplace {

    event Listed(uint256 indexed tokenId_, address indexed seller, uint256 price_);
    event Unlisted(uint256 indexed tokenId_);
    event Purchased(uint256 indexed tokenId_, address indexed buyer, uint256 price_);
    event AuctionStarted(uint256 indexed tokenId_, address indexed seller, uint256 startingPrice, uint256 endTime);
    event NewBid(uint256 indexed tokenId_, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed tokenId_, address indexed winner, uint256 finalBid);
    event AuctionCancelled(uint256 indexed tokenId_); 

    function putNftSale(uint256 tokenId_, uint256 price_) external payable;
    function unlistNftSale(uint256 tokenId_) external;
    function buyNft(uint256 tokenId_) external payable;
    function startAuction(uint256 tokenId_, uint256 startingPrice, uint256 duration) external;
    function bid(uint256 tokenId_) external payable;
    function endAuction(uint256 tokenId_) external;
    function cancelAuction(uint256 tokenId_) external; 
    function getAllSalePricesSorted() external view returns (uint256[] memory sortedtokenId_s, uint256[] memory sortedPrices);
}
