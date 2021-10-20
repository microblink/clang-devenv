#include <cstdlib>
#include <string>

int main( int argc, char * argv[] )
{
    std::string cmdline{ "flatpak run org.gnome.Epiphany" };
    for ( auto i{ 1 }; i < argc; ++i )
    {
        cmdline += ' ';
        cmdline += argv[ i ];
    }
    return system( cmdline.c_str() );
}
