Sub embedImagesInWriter(cFile)
    cURL = ConvertToURL( cFile )
    GlobalScope.BasicLibraries.LoadLibrary("Tools")
    oDoc = StarDesktop.loadComponentFromURL(cURL, "_blank", 0, (_
	    Array(MakePropertyValue("FilterName", "HTML (StarWriter)") ,MakePropertyValue( "Hidden", True ),)) 
    sFile = GetFileNameWithoutExtension(oDoc.url) + ".odt"
    sURL = ConvertToURL( sFile )
    allImages = oDoc.GraphicObjects
    for x = 0 to allImages.Count -1
      imageX = allImages.getByIndex(x)
      if InStr(1, imageX.GraphicURL, "vnd.sun.star.GraphicObject:", 0) = 0  then
        imageX.Graphic = getGraphicFromURL(imageX.GraphicURL)
      end if
    next
    
    oDoc.storeToURL( sURL, Array(_
	    MakePropertyValue( "FilterName", "writer8" ),)

    oDoc.close( True )
End Sub

Function getGraphicFromURL( sURL as String) as com.sun.star.graphic.XGraphic
    On Error Resume Next
    Dim oGraphicProvider as Object
    oGraphicProvider = createUnoservice("com.sun.star.graphic.GraphicProvider")
           
    Dim aMediaProperties(0) as New com.sun.star.beans.PropertyValue
    aMediaProperties(0).Name = "URL"
    aMediaProperties(0).Value = sURL

    getGraphicFromURL = oGraphicProvider.queryGraphic(aMediaProperties)
End Function

Function MakePropertyValue( Optional cName As String, Optional uValue ) _
   As com.sun.star.beans.PropertyValue
   Dim oPropertyValue As New com.sun.star.beans.PropertyValue
   If Not IsMissing( cName ) Then
      oPropertyValue.Name = cName
   EndIf
   If Not IsMissing( uValue ) Then
      oPropertyValue.Value = uValue
   EndIf
   MakePropertyValue() = oPropertyValue
End Function
