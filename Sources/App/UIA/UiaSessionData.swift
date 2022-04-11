//
//  UiaSessionData.swift
//  Based on Vapor's SessionData
//
//  Created by Charles Wright on 4/9/21.
//
import Foundation
import Vapor

public class UiaSessionData {
    //public var state: UiaaSessionState
    
    private var dict: [String:Any]
    public var snapshot: [String:Any] { self.dict }
    public var completed: [String]
    public var createdAt: Date
    
    public init() {
        //self.state = nil
        self.dict = [:]
        self.completed = []
        self.createdAt = Date()
    }
    
    /*
    public init(initialData data: [String:String], initialState: UiaaSessionState) {
        self.dict = data
        self.state = initialState
    }
    */
    
    public subscript(_ key: String) -> Any? {
        get { return self.dict[key] }
        set(newValue) { self.dict[key] = newValue }
    }
    
}
