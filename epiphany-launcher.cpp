#include <cstdlib>
#include <string>

#include <unistd.h>

int main( int argc, char * argv[] )
{
    std::string cmdline{ "xvfb-run -d flatpak run org.gnome.Epiphany" };
    for ( auto i{ 1 }; i < argc; ++i )
    {
        cmdline += ' ';
        cmdline += argv[ i ];
    }
	sleep( 1 ); // wait 1 second because dbus is slow in dying, which causes problems when launching the next instance of Epiphany
    return system( cmdline.c_str() );
}
