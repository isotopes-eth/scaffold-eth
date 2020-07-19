pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract NFTINK is BaseRelayRecipient, ERC721, Ownable {
    using ECDSA for bytes32;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter public totalInks;

    constructor() ERC721("Nifty Ink", "NFTINK") public {
      _setBaseURI('ipfs://ipfs/');
    }

    event newInk(uint256 id, address indexed artist, string inkUrl, string jsonUrl, uint256 limit);
    event mintedInk(uint256 id, string inkUrl, address to);

    struct Ink {
      uint256 id;
      address artist;
      address patron;
      string jsonUrl;
      string inkUrl;
      uint256 limit;
      uint256 count;
      bool exists;
    }

    mapping (string => uint256) private _inkIdByUrl;
    mapping (uint256 => Ink) private _inkById;
    mapping (string => EnumerableSet.UintSet) private _inkTokens;
    mapping (address => EnumerableSet.UintSet) private _artistInks;
    mapping (string => bytes) private _inkSignatureByUrl;

    function _createInk(string memory inkUrl, string memory jsonUrl, uint256 limit, address artist, address patron) internal returns (uint256) {

      totalInks.increment();

      Ink memory _ink = Ink({
        id: totalInks.current(),
        artist: artist,
        patron: patron,
        inkUrl: inkUrl,
        jsonUrl: jsonUrl,
        limit: limit,
        count: 0,
        exists: true
        });

        _inkIdByUrl[inkUrl] = _ink.id;
        _inkById[_ink.id] = _ink;
        _artistInks[artist].add(_ink.id);

        emit newInk(_ink.id, _ink.artist, _ink.inkUrl, _ink.jsonUrl, _ink.limit);

        return _ink.id;
    }

    function createInk(string memory inkUrl, string memory jsonUrl, uint256 limit) public returns (uint256) {
      require(!(_inkIdByUrl[inkUrl] > 0), "this ink already exists!");

      uint256 inkId = _createInk(inkUrl, jsonUrl, limit, _msgSender(), _msgSender());

      _mintInkToken(_msgSender(), inkId, inkUrl, jsonUrl);

      return inkId;
    }

    function _mintInkToken(address to, uint256 inkId, string memory inkUrl, string memory jsonUrl) internal returns (uint256) {
      _inkById[inkId].count += 1;

      _tokenIds.increment();
      uint256 id = _tokenIds.current();
      _inkTokens[inkUrl].add(id);

      _mint(to, id);
      _setTokenURI(id, jsonUrl);

      emit mintedInk(id, inkUrl, to);

      return id;
    }

    function mint(address to, string memory inkUrl) public returns (uint256) {
        uint256 _inkId = _inkIdByUrl[inkUrl];
        require(_inkId > 0, "this ink does not exist!");
        Ink storage _ink = _inkById[_inkId];
        require(_ink.artist == _msgSender(), "only the artist can mint!");
        require(_ink.count < _ink.limit || _ink.limit == 0, "this ink is over the limit!");

        uint256 tokenId = _mintInkToken(to, _inkId, _ink.inkUrl, _ink.jsonUrl);

        return tokenId;
    }

    //we will store the patronization signature on the weaker cahin to use on the stronger chain
    function allowPatronization(string memory inkUrl, bytes memory signature) public {
      uint256 _inkId = _inkIdByUrl[inkUrl];
      Ink storage _ink = _inkById[_inkId];
      bytes32 messageHash = getHash(_ink.artist,inkUrl,_ink.jsonUrl,_ink.limit);
      address signer = getSigner(messageHash, signature);
      require(signer == _ink.artist, "Artist did not sign these patronizing parameters.");
      _inkSignatureByUrl[inkUrl] = signature;
    }

    function patronize(string memory inkUrl, string memory jsonUrl, uint256 limit, address artist, bytes memory signature) public returns (uint256) {
      require(!(_inkIdByUrl[inkUrl] > 0), "this ink already exists!");

      require(artist!=address(0), "Artist must be specified.");
      bytes32 messageHash = getHash(artist,inkUrl,jsonUrl,limit);
      address signer = getSigner(messageHash, signature);
      require(signer == artist, "Artist did not sign these patronizing parameters.");

      uint256 inkId = _createInk(inkUrl, jsonUrl, limit, artist, _msgSender());

      _mintInkToken(_msgSender(), inkId, inkUrl, jsonUrl);

      return inkId;
    }

    function getHash(address artist, string memory inkUrl, string memory jsonUrl, uint256 limit) public view returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                byte(0x19),
                byte(0),
                address(this),
                artist,
                inkUrl,
                jsonUrl,
                limit
        ));
    }

    function getSigner(bytes32 signedHash, bytes memory signature) public pure returns (address)
    {
        return signedHash.toEthSignedMessageHash().recover(signature);
    }

    function inkTokenByIndex(string memory inkUrl, uint256 index) public view returns (uint256) {
      uint256 _inkId = _inkIdByUrl[inkUrl];
      require(_inkId > 0, "this ink does not exist!");
      Ink storage _ink = _inkById[_inkId];
      require(_ink.count >= index + 1, "this token index does not exist!");
      return _inkTokens[inkUrl].at(index);
    }

    function inkInfoByInkUrl(string memory inkUrl) public view returns (uint256, address, uint256, string memory, bytes memory) {
      uint256 _inkId = _inkIdByUrl[inkUrl];
      require(_inkId > 0, "this ink does not exist!");
      Ink storage _ink = _inkById[_inkId];
      bytes memory signature = _inkSignatureByUrl[inkUrl];

      return (_inkId, _ink.artist, _ink.count, _ink.jsonUrl, signature);
    }

    function inkIdByUrl(string memory inkUrl) public view returns (uint256) {
      return _inkIdByUrl[inkUrl];
    }

    function inksCreatedBy(address artist) public view returns (uint256) {
      return _artistInks[artist].length();
    }

    function inkOfArtistByIndex(address artist, uint256 index) public view returns (uint256) {
        return _artistInks[artist].at(index);
    }

    function inkInfoById(uint256 id) public view returns (string memory, address, uint256, string memory, bytes memory) {
      require(_inkById[id].exists, "this ink does not exist!");
      Ink storage _ink = _inkById[id];
      bytes memory signature = _inkSignatureByUrl[_ink.inkUrl];

      return (_ink.jsonUrl, _ink.artist, _ink.count, _ink.inkUrl, signature);
    }

    function versionRecipient() external virtual view override returns (string memory) {
  		return "1.0";
  	}

    function setTrustedForwarder(address _trustedForwarder) public onlyOwner {
      trustedForwarder = _trustedForwarder;
  	}

  	function getTrustedForwarder() public view returns(address) {
  		return trustedForwarder;
  	}

    function _msgSender() internal override(BaseRelayRecipient, Context) view returns (address payable) {
        return BaseRelayRecipient._msgSender();
    }

}
