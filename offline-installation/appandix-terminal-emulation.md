# Enabling Terminal Emulation in OpenLegacy Hub Enterprise  

To enable terminal emulation in OpenLegacy Hub Enterprise, you need to mount the required emulation JAR files into the Hub Enterprise container.  

## Downloading the Emulation JARs  

1. **Access the OpenLegacy Download Portal:**  
   - Visit [OpenLegacy Download Portal](https://download.openlegacy.com).  
   - If you don’t have credentials, contact your dedicated OpenLegacy Customer Success representative.  

2. **Navigate to the Emulation JARs:**  
   - Go to: **Adapters → Legacy Terminal Screens**  

3. **Download and Extract the Files:**  
   - Select the appropriate ZIP file for your use case.  
   - Download and extract its contents.  

## Mounting the JARs  

After extracting the files, place the JARs in the following directory:  

```sh
~/ol-hub-data/libs
```
Follow the installtion instructions and make sure to enable the screens in the installtion value files

---

In case you need to build the lowcode project with the screens artifacts make sure to copy the extracted ZIP content into your `.m2` directory