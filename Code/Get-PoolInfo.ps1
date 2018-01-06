. .\Code\PoolInfo.ps1

[Collections.Generic.Dictionary[string, PoolInfo]] $PoolCache = [Collections.Generic.Dictionary[string, PoolInfo]]::new()

function Get-PoolInfo([Parameter(Mandatory)][string] $folder) {
	<#  # old code
		$AllPools = Get-ChildItem "Pools" | Where-Object Extension -eq ".ps1" | ForEach-Object {
			Invoke-Expression "Pools\$($_.Name)"
		} | Where-Object { $_ -is [PoolInfo] -and $_.Profit -gt 0 }

		# find more profitable algo from all pools
		$AllPools = $AllPools | Select-Object Algorithm -Unique | ForEach-Object {
			$max = 0; $each = $null
			$AllPools | Where-Object Algorithm -eq $_.Algorithm | ForEach-Object {
				if ($max -lt $_.Profit) { $max = $_.Profit; $each = $_ }
			}
			if ($max -gt 0) { $each }
			Remove-Variable max
		}
	#>

	# get PoolInfo from all pools
	Get-ChildItem $folder | Where-Object Extension -eq ".ps1" | ForEach-Object {
		[PoolInfo] $pool = Invoke-Expression "$folder\$($_.Name)"
		if ($pool) {
			if ($PoolCache.ContainsKey($pool.Name)) {
				if ($pool.HasAnswer -or $pool.Enabled -ne $PoolCache[$pool.Name].Enabled) {
					$PoolCache[$pool.Name] = $pool
				}
				else {
					$PoolCache[$pool.Name].Algorithms | ForEach-Object {
						$_.Profit = $_.Profit * 0.99
					}
				}
			}
			else {
				$PoolCache.Add($pool.Name, $pool)
			}
		}
		Remove-Variable pool
	}

	# disble pools if not answer more then timeout
	$PoolCache.Values | Where-Object { $_.Enabled -and ([datetime]::Now - $_.AnswerTime).TotalMinutes -gt $Config.NoHashTimeout } | ForEach-Object {
		$_.Enabled = $false
	}

	# find more profitable algo from all pools
	$pools = [System.Collections.Generic.Dictionary[string, PoolAlgorithmInfo]]::new()
	$PoolCache.Values | Where-Object { $_.Enabled } | ForEach-Object {
		$_.Algorithms | ForEach-Object {
			if ($pools.ContainsKey($_.Algorithm)) {
				if ($pools[$_.Algorithm].Profit -lt $_.Profit) {
					$pools[$_.Algorithm] = $_
				}
			}
			else {
				$pools.Add($_.Algorithm, $_)
			}
		}
	}
	$pools.Values | ForEach-Object {
		$_
	}
}

function Out-PoolInfo {
	$PoolCache.Values | Format-Table @{ Label="Pool"; Expression = { $_.Name } },
		@{ Label="Enabled"; Expression = { $_.Enabled } },
		@{ Label="Answer ago"; Expression = { $ts = [datetime]::Now - $_.AnswerTime; if ($ts.TotalMinutes -gt $Config.NoHashTimeout) { "Unknown" } else { [SummaryInfo]::Elapsed($ts) } }; Alignment="Right" },
		@{ Label="Average Profit"; Expression = { $_.AverageProfit }; Alignment="Center" } |
		Out-Host
}

function Out-PoolBalance ([bool] $OnlyTotal) {
	$values = $PoolCache.Values | Where-Object { ([datetime]::Now - $_.AnswerTime).TotalMinutes -le $Config.NoHashTimeout } |
		Select-Object Name, @{ Name = "Confirmed"; Expression = { $_.Balance.Value } },
		@{ Name = "Unconfirmed"; Expression = { $_.Balance.Additional } },
		@{ Name = "Balance"; Expression = { $_.Balance.Value + $_.Balance.Additional } }
	if ($values -and $values.Length -gt 0) {
		$sum = $values | Measure-Object "Confirmed", "Unconfirmed", "Balance" -Sum
		if ($OnlyTotal) { $values.Clear() }
		$values += [PSCustomObject]@{ Name = "Total:"; Confirmed = $sum[0].Sum; Unconfirmed = $sum[1].Sum; Balance = $sum[2].Sum }
		Remove-Variable sum
	}
	$columns = [Collections.ArrayList]::new()
	$columns.AddRange(@(
		@{ Label="Pool"; Expression = { $_.Name } }
		@{ Label="Confirmed, $($Rates[0][0])"; Expression = { $_.Confirmed * $Rates[0][1] }; FormatString = "N$($Config.Currencies."$($Rates[0][0])")" }
		@{ Label="Unconfirmed, $($Rates[0][0])"; Expression = { $_.Unconfirmed * $Rates[0][1] }; FormatString = "N$($Config.Currencies."$($Rates[0][0])")" }
		@{ Label="Balance, $($Rates[0][0])"; Expression = { $_.Balance * $Rates[0][1] }; FormatString = "N$($Config.Currencies."$($Rates[0][0])")" }
	))
	# hack
	for ($i = 0; $i -lt $Rates.Count; $i++) {
		if ($i -eq 1) {
			$columns.AddRange(@(
				@{ Label="Balance, $($Rates[1][0])"; Expression = { $_.Balance * $Rates[1][1] }; FormatString = "N$($Config.Currencies."$($Rates[1][0])")" }
			))	
		}
		elseif ($i -eq 2) {
			$columns.AddRange(@(
				@{ Label="Balance, $($Rates[2][0])"; Expression = { $_.Balance * $Rates[2][1] }; FormatString = "N$($Config.Currencies."$($Rates[2][0])")" }
			))	
		}
	}

	$values | Format-Table $columns | Out-Host
	Remove-Variable columns, values
}