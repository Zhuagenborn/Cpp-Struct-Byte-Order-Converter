# *C/C++* Structure Byte Order Converter

![PowerShell](badges/PowerShell.svg)
![GitHub Actions](badges/Made-with-GitHub-Actions.svg)
![License](badges/License-MIT.svg)

## Introduction

This script can read a *C/C++* structure definition from the clipboard and generate byte reversing functions for the structure with `ntoh` or `hton` APIs.

## Usage

Suppose we have a structure `Foo`:

```c++
struct Foo {
    unsigned short us;
    int i8 : 8;
    int i24 : 24;
    signed long sl[4];
    char c[12];
    long long ll24 : 24;
    signed int si8 : 8;
    short s;
};
```

Copy the structure definition to the clipboard and run the script. We can get two reversing functions:

```c++
void ReverseFooToLittleEndian(Foo *const data) {
    data->us = ntohs(data->us);
    *(int*)((unsigned char*)(&data->us) + sizeof(data->us) + 0) = ntohl(*(int*)((unsigned char*)(&data->us) + sizeof(data->us) + 0));
    for (size_t i = 0; i < sizeof(data->sl) / sizeof(data->sl[0]); i++) {
        data->sl[i] = ntohl(data->sl[i]);
    }
    *(long long*)((unsigned char*)(&data->c) + sizeof(data->c) + 0) = ntohll(*(long long*)((unsigned char*)(&data->c) + sizeof(data->c) + 0));
    *(signed int*)((unsigned char*)(&data->c) + sizeof(data->c) + 8) = ntohl(*(signed int*)((unsigned char*)(&data->c) + sizeof(data->c) + 8));
    data->s = ntohs(data->s);
}

void ReverseFooToBigEndian(Foo *const data) {
    data->us = htons(data->us);
    *(int*)((unsigned char*)(&data->us) + sizeof(data->us) + 0) = htonl(*(int*)((unsigned char*)(&data->us) + sizeof(data->us) + 0));
    for (size_t i = 0; i < sizeof(data->sl) / sizeof(data->sl[0]); i++) {
        data->sl[i] = htonl(data->sl[i]);
    }
    *(long long*)((unsigned char*)(&data->c) + sizeof(data->c) + 0) = htonll(*(long long*)((unsigned char*)(&data->c) + sizeof(data->c) + 0));
    *(signed int*)((unsigned char*)(&data->c) + sizeof(data->c) + 8) = htonl(*(signed int*)((unsigned char*)(&data->c) + sizeof(data->c) + 8));
    data->s = htons(data->s);
}
```

The output can be copied directly to the clipboard:

```console
PS> .\Build-ByteReverseFunctions.ps1 | Set-Clipboard
```

### Warnings

- The structure name can only be extracted from the `struct` statement.
- The script can only detect single-line comments (`//`).
- The following settings may differ from the script on some systems and compilers.
  - Endianness.
  - The sizes of fundamental *C/C++* types.
  - The order of bit-fields.
  - Field alignment.

## License

Distributed under the *MIT License*. See `LICENSE` for more information.