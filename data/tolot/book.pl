use XML::Simple;
use List::Util;
my @theme_code_list = List::Util::shuffle ("5121","5122","5123","5124","5125","5126","5127","5128","5129","5130","5131","5132","6145","6146","6147","6148","6149","6150","6151","6152");

$book_xml = XMLin("./book.xml");

$book_xml->{title} = "Instagram";
$book_xml->{themeCode} = $theme_code_list[0];

print XMLout( $book_xml, NoAttr => 1, RootName => 'book',XMLDecl => "<?xml version='1.0' encoding='UTF-8'?>" );
