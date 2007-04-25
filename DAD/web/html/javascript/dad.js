var xmlhttp;

//----------------------------------//
// delete_bt_click(oVerify);
//   oVerify - object - field that will be examined to ensure that actual item is select before trying 
//     to delete it. This can point to either a SELECT or INPUT object.
//  will:
//    - prompt user to confirm that this should be deleted
//    - verify that something is selected
//    - record 'delete' as the action and then submit the form
function delete_bt_click(oVerify){
    var page = document.forms[0].document.all;
    var val = '';
    if( oVerify.nodeName == 'SELECT' ){
        val = oVerify[oVerify.selectedIndex].value;
    }else{
        if( oVerify.nodeName == 'INPUT' ){
            val = oVerify.value;
        }
    }
    if( val < 0 ){
        alert( 'Please select an item.' );
    }else{
        var TellMe = confirm( 'Are you sure you want to delete this?' );
        if ( TellMe ){
            record_action_and_submit('delete');
        }
    }
}

function remove_node(oFrom){
    var oWidth = oFrom.style.width;
    if( oFrom.selectedIndex >= 0 ){
        var str = oFrom.offsetWidth;
        var oSelected  = oFrom.children(oFrom.selectedIndex);
        oSelected.removeNode;
        oFrom.children(oFrom.selectedIndex).removeNode(true);
        oFrom.style.width = str;
    }

}


function copy_node(oFrom, oTo){
    var oSelected  = oFrom.children(oFrom.selectedIndex);
    var oNewNode   = document.createElement(oSelected.nodeName);
    var children = oFrom.children;
    var str = oTo.offsetWidth;
    oNewNode.value = oSelected.value;
    oNewNode.innerHTML = oSelected.innerHTML;
    oTo.appendChild(oNewNode);
    oTo.style.width = str;
}


function record_action_and_submit(oAction,oPrompt){
    var flg_cont = 0;
    if(oPrompt == 1){
        var TellMe = confirm( 'Are you sure?' );
        if ( TellMe ){
            flg_cont = 1;
        }
    }else{
        flg_cont = 1;
    }
    if( flg_cont == 1 ){
        var page = document.forms[0].document.all;
        page.form_action.value = oAction;
        document.forms[0].submit();
    }
}


function select_keypress_copy(oFrom, oTo, oFullList, strSep){
    if( typeof(strSep) == 'undefined' ){
        strSep = ',';
    }
    var page = document.forms[0].document.all;
    var key = window.event.keyCode;
    if( key == 13 ){
        copy_node(oFrom, oTo);
        record_list(oTo,oFullList,strSep);
    }
}


function select_keypress_record_action(oAction){
    var key = window.event.keyCode;
    if( key == 13 ){
        record_action_and_submit(oAction);
    }
}


//----------------------------------//
//  record_list(oFrom,oTo,oSep);
//  will build a separated list (using oSep) of values based on the full list of oFrom and store the list in oTo
//     oFrom - object | string - this needs to be the name (string) of the object rather than a reference 
//             to the object if record_list() is being called before the page is done loading
//     oTo   - object | string - (see oFrom), only difference is that this is where the data will be stored
//     oSep  - string - the string that will be used as a separater for the values. Default is comma (,)
function record_list(oFrom,oTo,oSep){
    var page = document.forms[0].document.all;
    var i;
    var str = '';
    if( typeof(oSep) == 'undefined' ){
        oSep = ',';
    }
    if( typeof(oFrom) == 'string' ){
        oFrom = document.getElementById(oFrom);
    }
    if( typeof(oTo) == 'string' ){
        oTo = document.getElementById(oTo);
    }
    for( i=0; i<oFrom.length; i++ ){
        obj = oFrom.children(i);
        if( obj.value !== '' ){
            str += oSep + obj.value;
        }
    }
    oTo.value = str;
    // if( typeof(oFrom) == 'string' ){
        // for( i=0; i<page[oFrom].length; i++ ){
            // obj = page[oFrom].children(i);
            // if( obj.value !== '' ){
                // str += oSep + obj.value;
            // }
        // }
        // page[oTo].value = str;
    // }
    // if( typeof(oFrom) === 'object' ){
        // for( i=0; i<oFrom.length; i++ ){
            // obj = oFrom.children(i);
            // if( obj.value !== '' ){
                // str += oSep + obj.value;
            // }
        // }
        // oTo.value = str;
    // }
}

//----------------------------------//
//  unlock_input_fields();
//    will unmark all fields that are currently 'readonly', so that the end user can change the data
function unlock_input_fields(){
    var page = document.forms[0].document.all;
    var i = 0;
    var type;
    var name;
    for( i=0; i<document.forms[0].elements.length; i++ ){
        type = document.forms[0].elements[i].type;
        type = type.toLowerCase();
        name = document.forms[0].elements[i].nodeName;
        name = name.toLowerCase();
        if( name == 'input' && type == 'text' ){
            //alert(document.forms[0].elements[i].value);
            document.forms[0].elements[i].readOnly = false;
        }
    }
}



function loadXMLDoc(url,dest){
    xmlhttp=null
    // code for Mozilla, etc.
    if (window.XMLHttpRequest){
        xmlhttp=new XMLHttpRequest()
    }
    // code for IE
    else if (window.ActiveXObject){
        xmlhttp=new ActiveXObject("Microsoft.XMLHTTP")
    }
    if (xmlhttp!=null){
        xmlhttp.onreadystatechange=state_Change(dest)
        xmlhttp.open("GET",url,true)
        xmlhttp.send(null)
    }else{
        alert("Your browser does not support XMLHTTP.")
    }
}

function state_Change(dest){
// if xmlhttp shows "loaded"
    if (xmlhttp.readyState==4){
        // if "OK"
        if (xmlhttp.status==200){
            document.getElementById(dest).innerHTML=xmlhttp.responseText
        }else{
            alert("Problem retrieving data:" + xmlhttp.statusText)
        }
    }
}