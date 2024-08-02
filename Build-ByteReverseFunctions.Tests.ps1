BeforeAll {
    Set-Clipboard ''
    . $PSScriptRoot/Build-ByteReverseFunctions.ps1
}

Describe 'Select-Converter' {
    Context 'Big-Endian to Little-Endian' {
        It "Returns '<Converter>' for '<Type>'" -TestCases @(
            @{ Type = 'short'; Converter = 'ntohs' },
            @{ Type = 'int'; Converter = 'ntohl' },
            @{ Type = 'long'; Converter = 'ntohl' },
            @{ Type = 'long long'; Converter = 'ntohll' },
            @{ Type = 'float'; Converter = 'ntohf' },
            @{ Type = 'double'; Converter = 'ntohd' },
            @{ Type = 'char'; Converter = '' },
            @{ Type = 'bool'; Converter = '' }
        ) {
            Select-Converter -Type $Type -LittleToBig:$false | Should -BeExactly $Converter
        }
    }

    Context 'Little-Endian to Big-Endian' {
        It "Returns '<Converter>' for ''" -TestCases @(
            @{ Type = 'short'; Converter = 'htons' },
            @{ Type = 'int'; Converter = 'htonl' },
            @{ Type = 'long'; Converter = 'htonl' },
            @{ Type = 'long long'; Converter = 'htonll' },
            @{ Type = 'float'; Converter = 'htonf' },
            @{ Type = 'double'; Converter = 'htond' }
            @{ Type = 'char'; Converter = '' },
            @{ Type = 'bool'; Converter = '' }
        ) {
            Select-Converter -Type $Type -LittleToBig:$true | Should -BeExactly $Converter
        }
    }
}

Describe 'Select-Name' {
    It "Selects the '<Name>' from '<Definitions>'" -TestCases @(
        @{ Name = 'Foo'; Definitions = 'struct Foo' },
        @{ Name = 'Foo'; Definitions = 'struct Foo {' },
        @{ Name = 'Foo'; Definitions = 'struct Foo { int i; };' }
    ) {
        Select-Name $Definitions | Should -BeExactly $Name
    }
}

Describe 'Select-Fields' {
    It "Selects fields from '<Definitions>'" -TestCases @(
        @{
            Definitions = @(
                'char c;',
                'unsigned short s;',
                'signed short int si;',
                'int i[4];',
                # Ignore comments.
                '// int i;',
                # Ignore pointers.
                'int *p;',

                # Two bit-fields form an integer. They belong to the same group.
                'long l : 16; long int li : 16;',
                # They are separate bit-fields in two groups since they have different signs.
                'unsigned long long ll : 20;',
                'signed long long int lli : 10;',

                'float f;',
                'double d;',
                'long double ld;',
                'bool b;'
            );
            Fields      = @(
                @{ Sign = 'Default'; Type = 'char'; Name = 'c'; IsArray = $false; Bits = 0; Group = 1 },
                @{ Sign = 'Unsigned'; Type = 'short'; Name = 's'; IsArray = $false; Bits = 0; Group = 2 },
                @{ Sign = 'Signed'; Type = 'short'; Name = 'si'; IsArray = $false; Bits = 0; Group = 3 },
                @{ Sign = 'Default'; Type = 'int'; Name = 'i'; IsArray = $true; Bits = 0; Group = 4 },
                @{ Sign = 'Default'; Type = 'long'; Name = 'l'; IsArray = $false; Bits = 16; Group = 5 },
                @{ Sign = 'Default'; Type = 'long'; Name = 'li'; IsArray = $false; Bits = 16; Group = 5 },
                @{ Sign = 'Unsigned'; Type = 'long long'; Name = 'll'; IsArray = $false; Bits = 20; Group = 6 },
                @{ Sign = 'Signed'; Type = 'long long'; Name = 'lli'; IsArray = $false; Bits = 10; Group = 7 },
                @{ Sign = 'Default'; Type = 'float'; Name = 'f'; IsArray = $false; Bits = 0; Group = 8 },
                @{ Sign = 'Default'; Type = 'double'; Name = 'd'; IsArray = $false; Bits = 0; Group = 9 },
                @{ Sign = 'Default'; Type = 'long double'; Name = 'ld'; IsArray = $false; Bits = 0; Group = 10 },
                @{ Sign = 'Default'; Type = 'bool'; Name = 'b'; IsArray = $false; Bits = 0; Group = 11 }
            )
        }
    ) {
        $ret = $Definitions | Select-Fields
        $ret.Count | Should -Be $Fields.Count
        for ($i = 0; $i -lt $ret.Count; $i++) {
            foreach ($key in $Fields[$i].Keys) {
                $ret[$i]."$key" | Should -Be $Fields[$i]."$key"
            }
        }
    }
}