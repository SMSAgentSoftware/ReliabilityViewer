# ReliabilityViewer

Reliability Viewer for Windows is a free application that displays reliability data for a local or remote computer.  
It is based on the concept of the built-in Windows Reliability Monitor, but allows you to also view data for remote computers (PS Remoting required), something the built-in monitor cannot do since Windows Vista.

The application allows you to review the entire reliability history for a computer in a datagrid, and enables you to filter the records to search for specific events.

The application can also generate a system stability chart using Microsoft Excel, which uses reliability metrics to give an overview of the stability of the system over time.

It is a useful troubleshooting tool to identify stability issues on a Windows system by reporting key system events such as

Application crashes
Software Update installations
MsiInstaller events
Unexpected system shutdowns
Blue-screens
Driver installations
Hardware failure

The application is coded in PowerShell using WPF for the UI, and MaterialDesigninXaml for the UI styling.

Documentation for use can be found on my blog:
http://smsagent.wordpress.com/tools/reliability-viewer-for-windows/
