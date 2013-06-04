function updateAlbumPhotoData(){
    (function(){
        $.ajax({
            url: URL_UPDATE_ALBUM_PHOTO_DATA,
            type: 'GET',
            cache: false,
            timeout: 300000,
            data: {
            },
            success:function(data){
                if(data.status != 'ok'){
                    alert("失敗しました / fail")
                }
                location.href = URL_THIS_PAGE;
            },
            error:function(jqXHR, textStatus, errorThrown){
                alert('失敗しました / fail');
            },
            beforeSend:function(){ block(); },
            complete:function(){ unblock(); },
            dataType: 'json'
        });
    })();
}

function downloadTlt(book_title, list){
    track_download_tlt_file();
    (function(book_title, list){
        $.ajax({
            url: URL_CREATE_ZIP,
            type: 'POST',
            cache: false,
            timeout: 300000,
            data: {
                book_title: book_title,
                images: list
            },
            success:function(data){
                if(data.status != 'ok'){
                    alert("失敗しました / fail")
                }
                location.href=data.url;
            },
            error:function(jqXHR, textStatus, errorThrown){
                alert('失敗しました / fail');
            },
            beforeSend:function(){ block(); },
            complete:function(){ unblock(); },
            dataType: 'json'
        });
    })(book_title, list);
}

function eraseData(){
    if(confirm('本当に初期化しますか？ / really?')){
        $('#erase_form').submit();
    }
}

function autoSelectFromStart(){
    $("#download_btn_list").html('');
    //console.log('-autoSelectFromStart-');
    var tolot_max_page_num = 62;
    photo_elms = $(".photo:not(.ignore)").get();

    var i = 1;
    var tmp_book_set = [];
    var book_set_list = [];

    $.each(photo_elms, function(){
        tmp_book_set.push($(this).attr('data-large-image-url'));

        if(i>=tolot_max_page_num){
            book_set_list.push(tmp_book_set);
            tmp_book_set = [];
            i=0;
        }
        i++;
    });
    if(tmp_book_set.length>0){
        book_set_list.push(tmp_book_set);
    }


    var book_num = 1;
    $.each(book_set_list, function(){
        var book_set = this;
        var add_class = '';
        if(book_set.length==62){
            add_class=" btn-success ";
        }
        var dl_link = $('<a class="btn btn-large '+add_class+'">download #'+book_num+' tlt set '+book_set.length+'/62</a>');

        dl_link.attr('data-img-url-list', book_set.join(','));

        dl_link.click( (function(book_num){ return function(){
            var list = $(this).attr('data-img-url-list').split(',');
            if(!(book_title = prompt('Please set Photo book Title / タイトルを入力してください\n(TOLOTに読み込ませた後、変更が可能です)', PHOTO_BOOK_TITLE_PREFIX+book_num))){
                return false;
            }
            if(book_title.length>18){
                alert("タイトルが18文字以上です。TOLOTで読み込ませる際にエラーがでるかもしれません\n(TOLOTに読み込ませた後、変更が可能です)");
            }

            downloadTlt(book_title, list);
            return false;
        }})(book_num) );

        dl_link.attr('href', '#');

        $("#download_btn_list").append(dl_link);

        book_num++;
    });

}

function setIgnoreImg(elm){
    var img = $(elm);
    if(img.hasClass('ignore')){// ignore済み
        img.removeClass('ignore');
        dataQueue.push({ method:'set_ignore_flag', val:{image:img.attr('data-large-image-url'), flag:0, data_source_table:img.attr("data-source-table") }});
    }else{
        img.addClass('ignore');
        dataQueue.push({ method:'set_ignore_flag', val:{image:img.attr('data-large-image-url'), flag:1, data_source_table:img.attr("data-source-table") }});
    }
    autoSelectFromStart();
};

var dataQueue = [];
var DELAY_DATA_SUBMIT_TIMER = 1000;

function delayDataSubmit(){
    if(dataQueue.length>0){
        indicate_progress();
        var d = dataQueue.pop();
        if(d.method=='set_ignore_flag'){
            //console.log(d);
            $.ajax({
                url: URL_SET_IGNORE_FLAG,
                type: 'POST',
                cache: false,
                timeout: 30000,
                data: d.val,
                success:function(data){
                    if(data.status != 'ok'){
                        alert("通信に失敗し、設定できませんでした / operation fail");
                    }else{
                        setTimeout(delayDataSubmit, DELAY_DATA_SUBMIT_TIMER);
                    }
                },
                error:function(jqXHR, textStatus, errorThrown){
                    alert("通信に失敗し、設定できませんでした / operation fail");
                },
                dataType: 'json'
            });
        }
    }else{
        deindicate_progress();
        setTimeout(delayDataSubmit, DELAY_DATA_SUBMIT_TIMER);
    }
}

$(function () {
    autoSelectFromStart();
    $("img.photo").lazyload();
    $("img.photo").click(function(){setIgnoreImg(this);});
    delayDataSubmit();
});
