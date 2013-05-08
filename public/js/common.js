function block() {
    $.blockUI({
        message:'<img src="img/loading.gif" width="112" height="150"><br>please wait!!<br>(verrrry long time require...)',
        css:{
            border:'none',
            lineHeight:'60px',
            textAlign:'center',
            verticalAlign:'center',
            '-webkit-border-radius':'10px',
            '-moz-border-radius':'10px',
            opacity:1,
            color:'#ffffff',
            backgroundColor:'transparent'
        }
    });
}

function unblock() {
    $.unblockUI();
}

//for InternetExplorer(don't have console.log())
if(typeof console != 'object'){ var console = {'log': function(){}}; } // hehe

