plugin.loadMainCSS();
plugin.loadLang(true);
 
plugin.onLangLoaded = function()
{
   this.addButtonToToolbar("proxy", "Proxy", "window.open ('https://@IP@/proxy/')", "help");
   this.addSeparatorToToolbar("help");
}
 
plugin.onRemove = function()
{
  this.removeButtonFromToolbar("link");
}
