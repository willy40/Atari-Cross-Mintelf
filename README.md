# Atari-Cross-Mintelf

## About

This project was inspired by the "Atari ST development" extension by dgisa: https://marketplace.visualstudio.com/items?itemName=dgis.atari-st-dev.

I decided in my spare time to write a script to build Vincent Riviere's m68k-Atari-Mintelf toolchain (http://vincent.riviere.free.fr/soft/m68k-atari-mintelf/) inside Docker. Once that was working, I reused parts of dgisa's extension to provide a devcontainer for building and debugging Atari ST C and assembly code inside a container.

The original extension authors did a great job — it's been a pleasure returning to the good old days and coding for the Atari ST again in C and assembler.


### Usage
To buid outside VScode just run:
`docker run --rm -v $(pwd):/workspace atari-mintelf-toolchain sh -c "make clean \&\& make"` debuginfo included,
`docker run --rm -v $(pwd):/workspace atari-mintelf-toolchain sh -c "make clean \&\& make release"` without debuginfo

Tested on Wsl2 ubuntu 26.04, in example direcotry run `code .`

Have fun.

