var loading_images = [
    '/img/loading0.gif',
    '/img/loading1.gif',
    '/img/loading2.gif',
];
$(function () {
    $.each(loading_images,function (){
        (new Image()).src =this;
    });
});

function block() {
    var imgurl = loading_images[Math.floor(Math.random() * loading_images.length)];
    $.blockUI({
        message:'<img src="'+imgurl+'" width="112" height="150"><br>please wait!!<br>(verrrry long time require...)',
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

function indicate_progress(){
    $("#non-modal-indicator").fadeIn();
}

function deindicate_progress(){
    $("#non-modal-indicator").fadeOut();
}

//for InternetExplorer(don't have console.log())
if(typeof console != 'object'){ var console = {'log': function(){}}; } // hehe

