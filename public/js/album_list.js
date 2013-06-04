function updateAlbumData(){
    (function(){
        $.ajax({
            url: URL_UPDATE_ALBUM_DATA,
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

function eraseData(){
    if(confirm('本当に初期化しますか？ / really?')){
        $('#erase_form').submit();
    }
}

$(function () {
});
