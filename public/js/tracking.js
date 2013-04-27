//load Google Analytics
(function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
(i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
})(window,document,'script','//www.google-analytics.com/analytics.js','ga');

ga('create', 'UA-19063513-5', 'cfe.jp');
ga('send', 'pageview');

//define helper
function track_login(e){
    ga('send', 'event', 'operation', 'login', 'login button');
}

function track_update_data(e){
    ga('send', 'event', 'operation', 'update_data', 'update data');
}

function track_download_tlt_file(e){
    ga('send', 'event', 'operation', 'download_tlt_file', 'download tlt file');
}
