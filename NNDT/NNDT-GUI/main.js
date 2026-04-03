const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 700,
    frame: false,
    transparent: true,
    resizable: false,
    maximizable: false,
    icon: path.join(__dirname, 'sndt_logo2.ico'),
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.loadFile('index.html');
}

app.whenReady().then(createWindow);

// Custom Window Controls
ipcMain.on('window-min', () => mainWindow.minimize());
ipcMain.on('window-close', () => app.quit());

// Window Resize via Frontend Slider (ANIMATED)
ipcMain.on('window-resize-animated', (event, targetScale) => {
    const baseW = 1100;
    const baseH = 700;
    const startBounds = mainWindow.getBounds();
    const endW = Math.round(baseW * targetScale);
    const endH = Math.round(baseH * targetScale);
    
    const duration = 300;
    const steps = 25;
    let currentStep = 0;
    
    const startW = startBounds.width;
    const startH = startBounds.height;
    
    if (mainWindow.resizeInterval) clearInterval(mainWindow.resizeInterval);
    
    mainWindow.resizeInterval = setInterval(() => {
        currentStep++;
        const progress = currentStep / steps;
        const ease = Math.sin(progress * Math.PI / 2);
        
        const curW = Math.round(startW + (endW - startW) * ease);
        const curH = Math.round(startH + (endH - startH) * ease);
        
        mainWindow.setBounds({
            x: startBounds.x,
            y: startBounds.y,
            width: curW,
            height: curH
        });
        
        if (currentStep >= steps) clearInterval(mainWindow.resizeInterval);
    }, duration / steps);
});

// Window Resize via Frontend Boot (INSTANT)
ipcMain.on('window-resize-instant', (event, targetScale) => {
    const baseW = 1100;
    const baseH = 700;
    const startBounds = mainWindow.getBounds();
    mainWindow.setBounds({
        x: startBounds.x,
        y: startBounds.y,
        width: Math.round(baseW * targetScale),
        height: Math.round(baseH * targetScale)
    });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
