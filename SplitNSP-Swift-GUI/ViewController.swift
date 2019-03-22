//
//  ViewController.swift
//  SplitNSP-Swift-GUI
//
//  Created by Feras Arabiat on 3/16/19.
//  Copyright © 2019 Feras Arabiat. All rights reserved.
//

import Cocoa
import ADragDropView
import CircularProgressMac

class ViewController: NSViewController, ADragDropViewDelegate {
    let startTime = Date()
    let splitSize:UInt64 = 0xFFFF0000 // 4,294,901,760 bytes
    let chunkSize = 0x8000 // 32,768 bytes
    var filePath = ""
    var partProgressValue = Progress(totalUnitCount: 0xFFFF0000)
    var nspProgressValue = Progress(totalUnitCount: 1)
    
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var splitNSPButton: NSButton!
    @IBOutlet weak var dragDropView: ADragDropView!
    @IBOutlet weak var nspProgress: CircularProgress!
    @IBOutlet weak var partProgress: CircularProgress!
    override func viewDidLoad() {
        super.viewDidLoad()

        dragDropView.delegate = self
        dragDropView.acceptedFileExtensions = ["nsp"]
        
        partProgress.progressInstance = partProgressValue
        nspProgress.progressInstance = nspProgressValue
        splitNSPButton.isEnabled = false
        nspProgress.isHidden = true
        partProgress.isHidden = true
    }

    @IBAction func splitNSPButtonClicked(_ sender: Any) {
        
        DispatchQueue.global(qos:.background).async {
            self.splitCopy(filePath:self.filePath)
        }
        dragDropView.isHidden = true
        nspProgress.isHidden = false
        partProgress.isHidden = false
        splitNSPButton.isEnabled = false
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    // when one file is dropped
    func dragDropView(_ dragDropView: ADragDropView, droppedFileWithURL URL: URL) {
        filePath = URL.path
        statusLabel.stringValue = filePath
        splitNSPButton.isEnabled = true
        nspProgressValue.totalUnitCount = Int64(getFileSize(filePath: filePath))
        print(filePath)
    }
    
    func dragDropView(_ dragDropView: ADragDropView, droppedFilesWithURLs URLs: [URL]) {
        filePath = ""
    }
    
    func getFileSize(filePath:String) -> UInt64 {
        var fileSize : UInt64 = 0
        
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: filePath)
            fileSize = attr[FileAttributeKey.size] as! UInt64
        } catch {
            print("Error: \(error)")
        }
        
        return fileSize
    }
    
    func deviceRemainingFreeSpaceInBytes() -> UInt64? {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last!
        guard
            let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: documentDirectory),
            let freeSize = systemAttributes[.systemFreeSize] as? NSNumber
            else {
                // something failed
                return nil
        }
        return freeSize.uint64Value
    }
    
    func splitCopy(filePath:String) {
        let fileSize =  getFileSize(filePath: filePath)
        print(fileSize)
        nspProgressValue.completedUnitCount = 0
        partProgressValue.completedUnitCount = 0

        if let info = deviceRemainingFreeSpaceInBytes() {
            print("free space: \(info)")
            
            if info < fileSize*2 {
                DispatchQueue.main.async {
                    print("Not enough free space to run. Will require twice the space as the NSP file")
                    self.statusLabel.stringValue = "Not enough free space to run. Will require twice the space as the NSP file"
                }
                
                return
            }
            
            print("Calculating number of splits...\n")
            
            let splitNum:Int = Int(fileSize / splitSize) + 1
            if splitNum == 1 {
                DispatchQueue.main.async {
                    print("This NSP is under 4GiB and does not need to be split.")
                    self.statusLabel.stringValue = "This NSP is under 4GiB and does not need to be split."
                }
                return
            }
            
            print("Splitting NSP into \(splitNum) parts...\n")
            
            let indexEndOfText = filePath.index(filePath.endIndex, offsetBy: -4)
            let dir = filePath[..<indexEndOfText] + "_split.nsp"
            let dirString:String = String(dir)
                        
            //remove folder if exists
            do {
                try FileManager.default.removeItem(atPath: dirString)
            }
            catch {
                print(error)
            }
            
            //create folder
            do {
                try FileManager.default.createDirectory(atPath: dirString, withIntermediateDirectories: true, attributes: nil)
            }
            catch {
                print(error)
                return
            }
            
            var remainingSize = fileSize
            var totalCompleted = 0

            if let inputStream = InputStream(fileAtPath: filePath) {
                inputStream.open()
                for i in (1...splitNum) {
                    autoreleasepool {
                        DispatchQueue.main.async {
                            print("Writing part \(i)/\(splitNum)")
                            self.statusLabel.stringValue = "Writing part \(i)/\(splitNum)"
                        }
                        
                        var partSize = 0
                        let fileName = String(format: "%02d", i - 1)
                        if let outStream = OutputStream(toFileAtPath: ("\(dir)/\(fileName)"), append: true) {
                            outStream.open()
                            
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
                            if remainingSize > splitSize {
                                partProgressValue.totalUnitCount = Int64(splitSize)
                                
                                while partSize < splitSize {
                                    autoreleasepool {
                                        inputStream.read(buffer, maxLength: chunkSize)
                                        outStream.write(buffer, maxLength: chunkSize)
                                        partSize += chunkSize
                                        totalCompleted += chunkSize
                                        
                                        partProgressValue.completedUnitCount = Int64(partSize)
                                        nspProgressValue.completedUnitCount = Int64(totalCompleted)
                                   }
                                }
                                
                                remainingSize -= splitSize
                            }
                            else {
                                partProgressValue.totalUnitCount = Int64(remainingSize)
                                
                                while partSize < remainingSize {
                                    autoreleasepool {
                                        let readLength = inputStream.read(buffer, maxLength: chunkSize)
                                        outStream.write(buffer, maxLength: readLength)
                                        partSize += readLength
                                        totalCompleted += readLength
                                        
                                        partProgressValue.completedUnitCount = Int64(partSize)
                                        nspProgressValue.completedUnitCount = Int64(totalCompleted)
                                    }
                                }
                            }
                            
                            buffer.deallocate()
                            outStream.close()
                        }
                        print("Part \(i) completed")
                        
                    }
                }
                inputStream.close()
                DispatchQueue.main.async {
                    print("NSP split completed!")
                    self.statusLabel.stringValue = "NSP split completed!"
                    self.nspProgress.isHidden = false
                    self.partProgress.isHidden = false
                    self.dragDropView.isHidden = true
                    self.splitNSPButton.isEnabled = false
                    self.filePath = ""
                }
                
            }
            
        } else {
            print("failed")
            return
        }
    }


}



