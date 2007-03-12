
//var mstrSmartTreeSpacerImagePath = "./images/Spacer.gif";
//var mstrSmartTreePlusImagePath = "./images/Plus.gif";
//var mstrSmartTreeMinusImagePath = "./images/Minus.gif";
//var mstrSmartTreeCollapsedBookImagePath = "./images/ClosedBook.gif";
//var mstrSmartTreeCollapsedFolderImagePath = "./images/ClosedFolder.gif";
//var mstrSmartTreeExpandedBookImagePath = "./images/OpenBook.gif";
//var mstrSmartTreeExpandedFolderImagePath = "./images/OpenFolder.gif";
//var mstrSmartTreeLeafImagePath = "./images/Document.gif";

var mstrSmartTreeSpacerImagePath = "images/Spacer.gif";
var mstrSmartTreePlusImagePath = "images/Plus.gif";
var mstrSmartTreeMinusImagePath = "images/Minus.gif";
var mstrSmartTreeCollapsedBookImagePath = "images/ClosedBook.gif";
var mstrSmartTreeCollapsedFolderImagePath = "images/ClosedFolder.gif";
var mstrSmartTreeExpandedBookImagePath = "images/OpenBook.gif";
var mstrSmartTreeExpandedFolderImagePath = "images/OpenFolder.gif";
var mstrSmartTreeLeafImagePath = "images/Document.gif";

var mfcnOnExpandCollapseHandler = null;

function displaySmartTree(strURL, strTree, strStartKey, blnUseEmbeddedXML)
{
   blnUseEmbeddedXML = (blnUseEmbeddedXML != null) ? blnUseEmbeddedXML : false;

   document.createStyleSheet('WebLIBSmartTreeStyles.asp');

   return displaySmartTreeBranch(strURL, strTree, strStartKey, "", 0, "", blnUseEmbeddedXML);
}

function displaySmartTreeSearchText(strURL, strTree, strSearchText, blnUseEmbeddedXML)
{
   return displaySmartTree(strURL, strTree, strSearchText, blnUseEmbeddedXML);
}

function displaySmartTreeBranch(strURL, strTree, strParentKey, strSearchText, intNodeLevel, strNode, blnUseEmbeddedXML)
{
   var intNode, intNodes;
   var strElement, strHTML, strKey, strText, strTip, strLaunchURL, strScript, strFrame, strCollapsedImage, strExpandedImage, strLeafImage, strChildren;
   var objXML, objTree;
   var objElement;

   blnUseEmbeddedXML = (blnUseEmbeddedXML != null) ? blnUseEmbeddedXML : false;

   if (intNodeLevel == 0)
   {
      objElement = document.all[strTree];

      objElement.innerHTML = "";
   }
   else
   {
      objElement = document.all["branch" + strTree + strNode];
   }

   if (objElement.innerHTML == "")
   {
      objXML = new ActiveXObject("Microsoft.XMLDOM");

      objXML.async = false;
      objXML.validateOnParse = false;
      objXML.preserveWhiteSpace = false;
      objXML.resolveExternals = false;

      if (strSearchText == "") {
         if (strURL.search(/\?/i) > -1) {
            objXML.load(strURL + '&strParentKey=' + escape(strParentKey));
         }
         else {
            objXML.load(strURL + '?strParentKey=' + escape(strParentKey));
         }
      }
      else {
         if (strURL.search(/\?/i) > -1) {
            objXML.load(strURL + '&strSearchText=' + escape(strSearchText));
         }
         else {
            objXML.load(strURL + '?strSearchText=' + escape(strSearchText));
         }
      }

      if (objXML.documentElement != null) {
         objTree = objXML.documentElement.childNodes;

         strHTML = '';

         if (objTree == null) {
            strHTML += '<SPAN CLASS="Node">Nothing to display</SPAN>';
         }
         else {
            strHTML += '<TABLE BORDER="0" CELLSPACING="0" CELLPADDING="0" STYLE="table-layout:fixed;">' +
                       '<COL>';

            var aobjChildNodes;

            intNodes = objTree.length;

            for (intNode = 0 ; intNode < intNodes ; intNode++) {
               aobjChildNodes = objTree[intNode].childNodes;

               strKey = aobjChildNodes[1].text;
               strText = blnUseEmbeddedXML ? aobjChildNodes[2].xml : aobjChildNodes[2].text;  // Choose xml or text property based on caller's preference
               strTip = aobjChildNodes[3].text;
               strLaunchURL = aobjChildNodes[4].text;
               strScript = aobjChildNodes[5].text;
               strFrame = aobjChildNodes[6].text;
               strCollapsedImage = aobjChildNodes[7].text;
               strExpandedImage = aobjChildNodes[8].text;
               strLeafImage = aobjChildNodes[9].text;
               strChildren = aobjChildNodes[10].text;

               if (strChildren == "" || typeof(strChildren) == "undefined") {
                  strHTML += displaySmartTreeNode(strURL, strTree, strKey, strText, strTip, strLaunchURL, strScript, strFrame, strCollapsedImage, strExpandedImage, strLeafImage, false, intNodeLevel, blnUseEmbeddedXML);
               }
         		else {
                  strHTML += displaySmartTreeNode(strURL, strTree, strKey, strText, strTip, strLaunchURL, strScript, strFrame, strCollapsedImage, strExpandedImage, strLeafImage, true, intNodeLevel, blnUseEmbeddedXML);
               }
         	}

            strHTML += '</TABLE>';
         }
         objElement.insertAdjacentHTML("beforeEnd", strHTML);
      }
   }

   return objXML;
}

function displaySmartTreeNode(strURL, strTree, strKey, strText, strTip, strLaunchURL, strScript, strFrame, strCollapsedImage, strExpandedImage, strLeafImage, blnHasChildren, intNodeLevel, blnUseEmbeddedXML) {
   var intNodeIndex
	var strNodeImage, strElement, strHTML, strNode

   blnUseEmbeddedXML = (blnUseEmbeddedXML != null) ? blnUseEmbeddedXML : false;
   
   strNode = getUniqueNodeID();

   strHTML = '<TR NOWRAP STYLE="position:relative">' +
             '<TD NOWRAP STYLE="position:relative" ALIGN="LEFT" HEIGHT="16" VALIGN="MIDDLE">';
	
   for (intNodeIndex = 1; intNodeIndex <= intNodeLevel; intNodeIndex++) {
      strHTML += '<IMG SRC="' + mstrSmartTreeSpacerImagePath + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="">' +
                 '<SPAN CLASS="Node" STYLE="position:relative">&nbsp;</SPAN>';
   }
	
   if (blnHasChildren) {
      strNodeImage = mstrSmartTreePlusImagePath;
		
      if (strExpandedImage != "" && strCollapsedImage != "") {
         strHTML += '<IMG ID="nod' + strTree + strKey + intNodeLevel.toString() + '" SRC="' + strNodeImage + '" ALIGN="TEXTTOP" ALT="" STYLE="cursor: hand; position: relative; top: -1px;" onclick="expandCollapse(' + "'" + strURL + "', '" + strTree + "', '" + strKey + "', '" + mstrSmartTreePlusImagePath + "', '" + mstrSmartTreeMinusImagePath + "', '" + getCollapsedImagePath(strCollapsedImage) + "', '" + getExpandedImagePath(strExpandedImage) + "', " + intNodeLevel.toString() + ", '" + strNode + "', " + blnUseEmbeddedXML + ');">' +
                    '<SPAN CLASS="Node" STYLE="position:relative">&nbsp;</SPAN>' +
                    '<IMG ID="img' + strTree + strNode + '" SRC="' + getCollapsedImagePath(strCollapsedImage) + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="">';
      }
      else {
         strHTML += '<IMG ID="nod' + strTree + strKey + intNodeLevel.toString() + '" SRC="' + strNodeImage + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="" STYLE="cursor : hand;" onclick="expandCollapse(' + "'" + strURL + "', '" + strTree + "', '" + strKey + "', '" + mstrSmartTreePlusImagePath + "', '" + mstrSmartTreeMinusImagePath + "', '', '', " + intNodeLevel.toString() + ", '" + strNode + "', " + blnUseEmbeddedXML + ');">';
      }
   }
   else {
      strHTML += '<IMG SRC="' + mstrSmartTreeSpacerImagePath + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="">';

      if (strLeafImage != "") {
         strHTML += '<SPAN CLASS="Node" STYLE="position:relative">&nbsp;</SPAN>' +
                    '<IMG SRC="' + getLeafImagePath(strLeafImage) + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="">';
      }
      else if (strExpandedImage != "" && strCollapsedImage != "") {
         strHTML += '<SPAN CLASS="Node" STYLE="position:relative">&nbsp;</SPAN>' +
                    '<IMG SRC="' + mstrSmartTreeSpacerImagePath + '" STYLE="position:relative" ALIGN="TEXTTOP" ALT="">';
      }
   }

   strHTML += '<SPAN CLASS="Node" STYLE="position:relative">&nbsp;</SPAN>';

   if (strLaunchURL != "") {
      strHTML += '<A ID="lnk' + strTree + strKey + intNodeLevel.toString() + '" TARGET="' + strFrame + '" TITLE="' + strTip + '" onClick="' + strScript + '" HREF="' + strLaunchURL + '" CLASS="Node">' +
                 strText +
                 '</A>';
   }
   else {
      strHTML += '<SPAN CLASS="Node" STYLE="position:relative">' +
                 strText +
                 '</SPAN>';
   }

   strHTML += '</TD>' +
              '</TR>';

   if (blnHasChildren) {
      strHTML += '<TR STYLE="display:none" STYLE="position:relative">' +
                 '<TD ID="branch' + strTree + strNode + '" CLASS="Node" STYLE="position:relative">' +
                 '</TD>' +
                 '</TR>';
   }

   return strHTML;
}

function collapseSmartTreeBranch(strTree, strNode)
{
   var objBranch = document.all("branch" + strTree + strNode);
   
   objBranch.parentElement.style.display = "none";

   // Call handler, if it exists (matching 'expand' event is in expandCollapse)
   if (mfcnOnExpandCollapseHandler != null) {
      mfcnOnExpandCollapseHandler(objBranch, false, null);
   }
}

function expandCollapse(strURL, strTree, strKey, strPlusImage, strMinusImage, strCollapsedImage, strExpandedImage, intNodeLevel, strNode, blnUseEmbeddedXML)
{
   var objSource = event.srcElement;
   var aobjAll = document.all;
	var objBranch = aobjAll["branch" + strTree + strNode];
	var objXML;
	
   blnUseEmbeddedXML = (blnUseEmbeddedXML != null) ? blnUseEmbeddedXML : false;
   
	if (objBranch != null) {
		if (objBranch.parentElement.style.display == "") {
         objSource.src = strPlusImage;

         if (aobjAll["img" + strTree + strNode] != null) {
            aobjAll["img" + strTree + strNode].src = strCollapsedImage;
         }

			collapseSmartTreeBranch(strTree, strNode);
		}
		else {
         objSource.src = strMinusImage;

         if (aobjAll["img" + strTree + strNode] != null) {
            aobjAll["img" + strTree + strNode].src = strExpandedImage;
         }

         objBranch.parentElement.style.display = "";

         if (objBranch.innerHTML == "") {
		   	objXML = displaySmartTreeBranch(strURL, strTree, strKey, "", intNodeLevel + 1, strNode, blnUseEmbeddedXML);
         }

         // Call handler, if it exists (matching 'collapse' event is in collapseSmartTreeBranch)
         if (mfcnOnExpandCollapseHandler != null) {
            mfcnOnExpandCollapseHandler(objBranch, true, objXML);
         }
		}
	}

	return objXML;
}

function expandToNode(strURL, strTree, strExpandKey)
{
   var intNode, intNodes;
   var strKey;
   var objXML, objTree, objExpand;

   objXML = new ActiveXObject("Microsoft.XMLDOM");

   objXML.async = false;
   objXML.validateOnParse = false;
   objXML.preserveWhiteSpace = false;
   objXML.resolveExternals = false;

   if (strURL.search(/\?/i) > -1) {
      objXML.load(strURL + '&strKey=' + escape(strExpandKey));
   }
   else {
      objXML.load(strURL + '?strKey=' + escape(strExpandKey));
   }

   objTree = objXML.documentElement.childNodes;

   if (objTree != null) {
      var aobjAll = document.all;

      intNodes = objTree.length;

      for (intNode = intNodes - 1 ; intNode >= 0 ; intNode--) {
         strKey = objTree[intNode].childNodes[1].text;

         objExpand = aobjAll["nod" + strTree + strKey + (intNodes - intNode - 1).toString()];

         if (objExpand != null) {
            objExpand.click();
         }
      }
   }
   
   return objXML;
}

function openSmartTreeNode(strURL, strTree, strKeyPath) {
   var astrKeys = strKeyPath.split("/");
   var lngKeyCount = astrKeys.length;
   var i;
   var aobjAll = document.all;
   var objTree = aobjAll[strTree];
   var objExpand;
   var objLink;
   
   for (i = 0; i < lngKeyCount - 1; i++) {
      objExpand = aobjAll["nod" + strTree + astrKeys[i] + i.toString()];

      if (objExpand != null) {
         if (objExpand.src.indexOf(mstrSmartTreePlusImagePath) != -1) {
            objExpand.click();
         }
      }
      else {
         return false;
         break;
      }
   }
   
   // All branches have been expanded - now find the node to activate
   if (i == lngKeyCount - 1) {
      objLink = aobjAll["lnk" + strTree + astrKeys[i] + i.toString()];
      objLink.focus();
      objLink.click();
      return true;
   }
   else {
      return false;
   }
}

function changeNodeImage(objNode, strImage)
{
   objNode.src = (strImage == "" || typeof(strImage) == "undefined") ? mstrSmartTreeSpacerImagePath : strImage;
}

function setOnExpandCollapseHandler(fcnHandler) {
   mfcnOnExpandCollapseHandler = fcnHandler;
}

function getUniqueNodeID()
{
   return Math.random().toString();
}

function getPlusImagePath()
{
   return mstrSmartTreePlusImagePath;
}

function getMinusImagePath()
{
   return mstrSmartTreeMinusImagePath;
}

function getSpacerImagePath()
{
   return mstrSmartTreeSpacerImagePath;
}

function getCollapsedImagePath(strImage)
{
   if (strImage == "" || typeof(strImage) == "undefined") {
      return "";
   }
   else if (strImage.toUpperCase() == "_CLOSEDBOOK") {
      return mstrSmartTreeCollapsedBookImagePath;
   }
   else if (strImage.toUpperCase() == "_CLOSEDFOLDER") {
      return mstrSmartTreeCollapsedFolderImagePath;
   }
   else {
      return strImage;
   }
}

function getExpandedImagePath(strImage)
{
   if (strImage == "" || typeof(strImage) == "undefined") {
      return "";
   }
   else if (strImage.toUpperCase() == "_OPENBOOK") {
      return mstrSmartTreeExpandedBookImagePath;
   }
   else if (strImage.toUpperCase() == "_OPENFOLDER") {
      return mstrSmartTreeExpandedFolderImagePath;
   }
   else {
      return strImage;
   }
}

function getLeafImagePath(strImage)
{
   if (strImage == "" || typeof(strImage) == "undefined") {
      return "";
   }
   else if (strImage.toUpperCase() == "_DOCUMENT") {
      return mstrSmartTreeLeafImagePath;
   }
   else {
      return strImage;
   }
}

