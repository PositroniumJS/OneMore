<#
.SYNOPSIS
Generates the OneMoreAddin.com static HTML pages by extracting the archived
OneMoreWiki.zip file and wrapping each page in the template.htm file

.PARAMETER zipfile
The path to the OneMoreWiki.zip file
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string] $ZipFile
    )

Begin
{
    $script:RootUrl = 'https://onemoreaddin.com'
    $script:UrlSetSchema = 'http://www.sitemaps.org/schemas/sitemap/0.9'
    $script:FileOrder = '__File_Order.txt'
    $script:ZipName = 'OneMore Wiki'
    $script:sitemap = $null

    function MakeSiteMap
    {
        $null = [Reflection.Assembly]::LoadWithPartialName("System.Xml.Linq")
        $script:sitemap = [System.Xml.Linq.XElement]::Parse("<urlset xmlns=""$UrlSetSchema""/>")
        AddToSiteMap $RootUrl 1.0
    }

    function AddToSiteMap
    {
        param([string]$url, [decimal]$priority)
        $date = get-date ((Get-Date).ToUniversalTime()) -format 'yyyy-MM-ddThh:mm:ss+00:00'
        $sitemap.Add([System.Xml.Linq.XElement]::new(([System.Xml.Linq.XNamespace]$UrlSetSchema) + 'url',
            [System.Xml.Linq.XElement]::new('loc', [Uri]::EscapeUriString($url)),
            [System.Xml.Linq.XElement]::new('lastmod', $date),
            [System.Xml.Linq.XElement]::new('priority', $priority.ToString('0.0'))
            )
        )
    }

    function Unpack
    {
        param([string] $file)
        $pref = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'
        Write-Host "extracting $file"
        Expand-Archive -Path $file -DestinationPath ./ -Force | Out-Null
        $global:ProgressPreference = $pref
    }

    function MakeSection
    {
        param($sectionName)
        $sectionID = $sectionName.ToLower().Replace(' ', '-').Replace('.', '-')
        Write-Host "section '$sectionName' ($sectionID)" -ForegroundColor Blue

        $dir = Join-Path $ZipName $sectionName
        $toc, $first = MakeSectionTOC $sectionID $sectionName

        Get-ChildItem $dir -File *.htm | foreach {
            $id = MakePage $sectionID $_.Name $_.FullName $toc
        }

        $indexFile = Join-Path $dir 'index.html'
        $meta = "<meta http-equiv=""refresh"" content=""0; url=$first"" />"
        $meta | Out-File $indexFile -Encoding utf8 -Force -Confirm:$false

        return $dir, $sectionID
    }

    function MakeSectionTOC
    {
        param($sectionID, $sectionName)
        $toc = @()
        $first = $null
        $file = (Join-Path $ZipName (Join-Path $sectionName $FileOrder)) | Resolve-Path
        if (Test-Path $file)
        {
            # use FileOrder.txt
            Get-Content $file -Encoding utf8 | foreach {
                $id = $_.ToLower().Replace(' ', '-').Replace('.', '-')
                $name = "$_`.htm"
                $toc += "<li><a id=""$id"" href=""$name"">$($_)</a></li>"
                if (!$first) { $first = "/$sectionID/$name" }
            }

            Write-Host "deleting $file" -ForegroundColor Yellow
            Remove-Item $file -Force -Confirm:$false
        }
        else
        {
            Write-Host "file does not exist $file" -ForegroundColor Red
            # no FileOrder.txt so discover HTM files instead
            Get-ChildItem (Join-Path $ZipName $sectionName) -File *.htm | foreach {
                $id = $_.BaseName.ToLower().Replace(' ', '-').Replace('.', '-')
                $name = "$($_.BaseName)`.htm"
                $toc += "<li><a id=""$id"" href=""$name"">$($_)</a></li>"
                if (!$first) { $first = "/$sectionID/$name" }
            }
        }

        return $toc, $first
    }

    function MakePage
    {
        param($sectionID, $pageName, $pageFile, $toc)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($pageName)
        $pageID = $name.ToLower().Replace(' ', '-').Replace('.', '-')
        Write-Host "page '$name' ($pageID)"

        $source = Get-Content -Path $pageFile -Encoding utf8 -Raw
        $html = New-Object -Com 'HTMLFile'
        $html.IHTMLDocument2_write($source)
        $body = $html.all.tags('body') | foreach InnerHtml

        $template = Get-Content -Path template.htm -Encoding utf8 -Raw
        $template = $template.Replace('~TOC~', [string]::join("`n", $toc))
        $template = $template.Replace('~sectionID~', $sectionID)
        $template = $template.Replace('~content~', $body)

        $template | Out-File $pageFile -Encoding utf8 -Force -Confirm:$false

        AddToSiteMap "$RootUrl/$sectionID/$name`.htm" 0.5

        return $pageID
    }
}
Process
{
    MakeSiteMap

    if ($ZipFile -and (Test-Path $ZipFile))
    {
        $script:ZipName = (Get-Item $ZipFile).BaseName
        Unpack $ZipFile
    }

    Get-ChildItem $ZipName -Directory | foreach {
        $name = $_.Name
        $dir, $sectionID = MakeSection $name

        if (Test-Path $name)
        {
            # delete the old section folder
            Remove-Item $name -Recurse -Force -Confirm:$false
        }

        # move the new section folder up a level and rename
        Move-Item $dir ./$sectionID -Force -Confirm:$false
    }

    Write-Host 'saving sitemap.xml'
    $sitemap.ToString() | Out-File 'sitemap.xml'

    Remove-Item $ZipName -Force -Confirm:$false
}
