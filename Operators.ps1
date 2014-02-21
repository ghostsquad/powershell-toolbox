# ---------------------------------------------------------------------------
# Name:   Invoke-Ternary
# Alias:  ?:
# Author: Karl Prosser
# URL: http://blogs.msdn.com/b/powershell/archive/2006/12/29/dyi-ternary-operator.aspx?Redirected=true
# Desc:   Similar to the C# ? : operator e.g. 
#            _name = (value != null) ? String.Empty : value;
# Usage:  1..10 | ?: {$_ -gt 5} {"Greater than 5";$_} {"Not greater than 5";$_}
# ---------------------------------------------------------------------------
filter Invoke-Ternary ([scriptblock]$decider, [scriptblock]$ifTrue, [scriptblock]$ifFalse) 
{
   if (&$decider) { 
      &$ifTrue
   } else { 
      &$ifFalse 
   }
}
New-Alias -Name '?:' -Value 'Invoke-Ternary'