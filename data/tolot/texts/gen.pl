use File::Slurp;

for($i=0;$i<62;$i++){
	$str = << "EOS";
<?xml version='1.0' encoding='utf-8' standalone='no'?>
<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.1//EN' 'http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd'>
<html>
  <head>
  </head>
  <body class='tolot' data-page-type='page' >
    <article class='tolot' data-tag-type='item' data-item-type='image'><img src='../images/$i.jpg' /></article>
  </body>
</html>
EOS
	write_file("page$i.xhtml", $str);
}




