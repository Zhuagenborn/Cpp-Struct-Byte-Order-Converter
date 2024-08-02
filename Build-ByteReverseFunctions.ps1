<#
.SYNOPSIS
    Read a C/C++ structure definition from the clipboard and generate byte reversing functions for the structure with `ntoh` or `hton` APIs.
.DESCRIPTION
    This script can generate byte reversing functions for a C/C++ structure definition.
    Suppose we have a structure `Foo`:
    ```c++
    struct Foo {
        short s;
        int i;
        long l;
        long long ll[4];
    };
    ```
    Copy the structure definition to the clipboard and run the script. We can get two reversing functions:
    ```c++
    void ReverseFooToLittleEndian(Foo *const data) {
        data->s = ntohs(data->s);
        data->i = ntohl(data->i);
        data->l = ntohl(data->l);
        for (size_t i = 0; i < sizeof(data->ll) / sizeof(data->ll[0]); i++) {
            data->ll[i] = ntohll(data->ll[i]);
        }
    }

    void ReverseFooToBigEndian(Foo *const data) {
        data->s = htons(data->s);
        data->i = htonl(data->i);
        data->l = htonl(data->l);
        for (size_t i = 0; i < sizeof(data->ll) / sizeof(data->ll[0]); i++) {
            data->ll[i] = htonll(data->ll[i]);
        }
    }
    ```
.PARAMETER Noexcept
    Whether to add the C++ `noexcept` specifier.
.OUTPUTS
    Two C/C++ byte reversing functions.
.EXAMPLE
    PS> .\Build-ByteReverseFunctions.ps1
    The script reads a C/C++ structure definition from the clipboard and output byte reversing functions to the console.
.EXAMPLE
    PS> .\Build-ByteReverseFunctions.ps1 | Set-Clipboard
    The script reads a C/C++ structure definition from the clipboard and output byte reversing functions to the clipboard.
.NOTES
    - The structure name can only be extracted from the `struct` statement.
    - The script can only detect single-line comments.
    - The following settings may differ from the script on some systems and compilers.
      - Endianness.
      - The sizes of fundamental C/C++ types.
      - The order of bit-fields.
      - Field alignment.
#>

[CmdletBinding()]
param(
    [switch]$Noexcept
)

# Sizes of integer types.
$sizes = @{
    'char'      = 1;
    'short'     = 2;
    'int'       = 4;
    # On some 64-bit systems, the size of `long` is 8 bytes.
    'long'      = 4;
    'long long' = 8;
}

# Signs of integer types.
enum Sign {
    Default
    Signed
    Unsigned
}

<#
.SYNOPSIS
    Format a sign type to a C/C++ keyword.
#>
function Format-Sign {
    param (
        [Parameter(Mandatory)]
        [Sign]$Sign
    )

    switch ($Sign) {
        Signed { return 'signed' }
        Unsigned { return 'unsigned' }
        Default { return '' }
    }
}

# The C/C++ field definition.
class Field {
    [Sign] $Sign
    [string] $Name
    [string] $Type
    # The bit-fields packed to the same underlying integer belong to the same group.
    [uint] $Group
    [uint] $Bits
    [bool] $IsArray

    [string] ToString() {
        return "$(Format-Sign $this.Sign) $($this.Type) $($this.Name)$($this.IsArray ? '[]' : '')$($this.Bits -gt 0 ? (' : ' + $this.Bits) : '')".Trim()
    }
}

<#
.SYNOPSIS
    Convert the matching regex groups in a C/C++ field definition string to a `Field` object.
#>
function ConvertTo-Field {
    param (
        [Parameter(Mandatory)]
        [Object[]]$RegexGroups
    )

    $field = [Field]::new()

    $sign = $RegexGroups[1].Value.Trim()
    $field.Sign = [string]::IsNullOrEmpty($sign) ? [Sign]::Default : ($sign -eq 'unsigned' ? [Sign]::Unsigned : [Sign]::Signed)

    $long = $RegexGroups[2].Value.Trim()
    $len = $RegexGroups[3].Value.Trim()
    $int = $RegexGroups[4].Value.Trim()
    if ($len -eq 'int' -and [string]::IsNullOrEmpty($int)) {
        $len = ''
        $int = 'int'
    }

    $field.Type = "$long $len".Trim()
    if ([string]::IsNullOrEmpty($field.Type)) {
        $field.Type = $int
    }

    $field.Name = $RegexGroups[5].Value.Trim()
    $field.IsArray = ![string]::IsNullOrWhiteSpace($RegexGroups[6].Value)
    $field.Bits = [uint]$RegexGroups.Groups[7].Value.Trim()
    return $field
}

<#
.SYNOPSIS
    Select the structure name from a C/C++ structure definition.
#>
function Select-Name {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $rgx = [regex]'\bstruct\s+(\w+)'

    foreach ($line in $Lines) {
        $line = Select-Code $line
        if (![string]::IsNullOrEmpty($line)) {
            $match = $rgx.Match($line)
            if ($match.Success) {
                return $match.Groups[1].Value.Trim()
            }
        }
    }

    return ''
}

<#
.SYNOPSIS
    Select code and remove single-line comments in a line.
#>
function Select-Code {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    return ($Line -replace '//.*$', '').Trim()
}

<#
.SYNOPSIS
    Select `Field` objects from C/C++ field definition strings.
#>
function Select-Fields {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Line
    )

    begin {
        New-Variable -Name 'byte_len' -Value 8 -Option Constant
        $rgx = [regex]'\b(?:((?:un)?signed)\s+)?(?:(long)\s+)?(?:(\w+)\s+)?(?:(int)\s+)?(\w+)\s*(?:\[\s*(\w+)\s*\])?(?:\s*:\s*(\d*))?;'
        $group = 0
        $prev_type = ''
        $prev_sign = [Sign]::Default
        $total_bits = 0
        $max_bits = 0
    }

    process {
        $Line = Select-Code $Line
        if (![string]::IsNullOrEmpty($Line)) {
            foreach ($match in $rgx.Matches($Line)) {
                if ($match.Success) {
                    $field = ConvertTo-Field $match.Groups
                    if (![string]::IsNullOrEmpty($field.Type) -and ![string]::IsNullOrEmpty($field.Name)) {
                        if ($field.Bits -eq 0) {
                            $group++
                        } else {
                            if (($total_bits -eq 0) -or ($total_bits + $field.Bits -gt $max_bits) -or ($prev_type -ne $field.Type) -or ($prev_sign -ne $field.Sign)) {
                                if (!($sizes.Keys -contains $field.Type)) {
                                    throw "Unsupported bit-field: '$($match.Value.Trim())'"
                                }

                                $group++
                                $max_bits = $sizes[$field.Type] * $byte_len
                                $prev_type = $field.Type
                                $prev_sign = $field.Sign
                                $total_bits = 0
                            }

                            $total_bits += $field.Bits
                        }

                        $field.Group = $group
                        Write-Output $field
                    }
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Select a byte reversing function for a basic type.
#>
function Select-Converter {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$Type,

        [switch]$LittleToBig
    )

    $hton = @{
        'short'     = 'htons';
        'int'       = 'htonl';
        'long'      = 'htonl';
        'long long' = 'htonll';
        'float'     = 'htonf';
        'double'    = 'htond';
    }

    $ntoh = @{
        'short'     = 'ntohs';
        'int'       = 'ntohl';
        'long'      = 'ntohl';
        'long long' = 'ntohll';
        'float'     = 'ntohf';
        'double'    = 'ntohd';
    }

    $funcs = $LittleToBig ? $hton : $ntoh
    if ($funcs.Keys -contains $Type) {
        return $funcs[$Type]
    } else {
        return ''
    }
}

<#
.SYNOPSIS
    Generate a byte reversing function for a C/C++ structure.
#>
function Build-ReverseFunction {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$Name,

        [Parameter(Mandatory)]
        [Object[]]$Fields,

        [switch]$LittleToBig,

        [switch]$Noexcept
    )

    $prev_field = [Field]::new()
    $prev_non_bit_field = [Field]::new()
    $continuous_bits_size = 0

    New-Variable -Name 'param' -Value 'data' -Option Constant
    New-Variable -Name 'byte' -Value 'unsigned char' -Option Constant
    Write-Output "void Reverse$($Name)To$($LittleToBig ? 'BigEndian' : 'LittleEndian')($Name *const $param)$($Noexcept ? ' noexcept ' : ' '){"

    foreach ($field in $Fields) {
        if ($prev_field.Group -ne $field.Group) {
            $type = $field.Type
            $name = $field.Name
            $func = Select-Converter -Type $type -LittleToBig:$LittleToBig
            if (![string]::IsNullOrEmpty($func)) {
                if (!$field.IsArray) {
                    if ($field.Bits -eq 0) {
                        Write-Output "    $param->$name = $func($param->$name);"
                    } else {
                        $sign = Format-Sign $field.Sign
                        $sign_type = "$sign $type".Trim()
                        $prev_non_bit_name = $prev_non_bit_field.Name
                        if ([string]::IsNullOrEmpty($prev_non_bit_name)) {
                            Write-Output "    *($sign_type*)(($byte*)$param + $continuous_bits_size) = $func(*($sign_type*)(($byte*)$param + $continuous_bits_size));"
                        } else {
                            Write-Output "    *($sign_type*)(($byte*)(&$param->$prev_non_bit_name) + sizeof($param->$prev_non_bit_name) + $continuous_bits_size) = $func(*($sign_type*)(($byte*)(&$param->$prev_non_bit_name) + sizeof($param->$prev_non_bit_name) + $continuous_bits_size));"
                        }

                        if ($sizes.Keys -contains $type) {
                            # Field alignment may affect field offsets.
                            $continuous_bits_size += $sizes[$type]
                        } else {
                            throw "Unsupported bit-field: $field"
                        }
                    }
                } else {
                    Write-Output "    for (size_t i = 0; i < sizeof($param->$name) / sizeof($param->$name[0]); i++) {"
                    Write-Output "        $param->$name[i] = $func($param->$name[i]);"
                    Write-Output '    }'
                }
            }

            $prev_field = $field
            if ($field.Bits -eq 0) {
                $prev_non_bit_field = $field
                $continuous_bits_size = 0
            }
        }
    }

    Write-Output '}'
}

try {
    $lines = Get-Clipboard
    if (![string]::IsNullOrWhiteSpace($lines)) {
        $name = Select-Name $lines
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = '<NAME>'
        }

        $fields = $lines | Select-Fields
        if ($fields) {
            Build-ReverseFunction -Fields $fields -Name $name -Noexcept:$Noexcept -LittleToBig:$false
            Write-Output $([Environment]::NewLine)
            Build-ReverseFunction -Fields $fields -Name $name -Noexcept:$Noexcept -LittleToBig:$true
        }
    }
} catch {
    Write-Host $_ -ForegroundColor Red
}